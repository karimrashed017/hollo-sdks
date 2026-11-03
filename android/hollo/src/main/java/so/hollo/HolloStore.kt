package so.hollo

import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

// The SDK's state: the conversation, the unread count and whether the chat is
// on screen, plus polling and the offline queue. Mirrors the React Native
// store; the Compose UI and Hollo's public API both build on it.

/** A message the user wrote that the server hasn't confirmed yet. */
internal data class PendingMessage(val localId: String, val body: String)

internal data class HolloState(
    val started: Boolean = false,
    val open: Boolean = false,
    val messages: List<HolloMessage> = emptyList(),
    /** Written but not sent yet, oldest first; sent again when the connection is back. */
    val pending: List<PendingMessage> = emptyList(),
    val unread: Int = 0,
    val error: String? = null,
    /** The last request couldn't reach the server at all. */
    val offline: Boolean = false,
    val profile: HolloProfile = HolloProfile(),
    val push: HolloPushSettings = HolloPushSettings(),
    /** Show the "Runs on Hollo" footer. The server decides. */
    val branding: Boolean = true,
    /** This device sent Hollo a push token. */
    val pushRegistered: Boolean = false,
    /** Show the in-chat card asking to turn on notifications (F-40). */
    val askPush: Boolean = false,
)

internal const val OPEN_POLL_MS = 3_000L
internal const val CLOSED_POLL_MS = 30_000L
internal const val PUSH_TOKEN = "pushToken"
private const val PUSH_ASKED = "pushAsked"

internal class HolloStore(private val scope: CoroutineScope) {
    private val _state = MutableStateFlow(HolloState())
    val state: StateFlow<HolloState> = _state.asStateFlow()

    private val _unread = MutableStateFlow(0)
    val unread: StateFlow<Int> = _unread.asStateFlow()

    @Volatile
    private var client: HolloClient? = null
    private var poller: Job? = null
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private val sendLock = Mutex()
    private val accountLock = Mutex()
    private val rejected = ConcurrentHashMap<String, Exception>()
    private val visibleChats = AtomicInteger(0)

    /** Bumped when the conversation is swapped (identify, sign-out), so stale polls are dropped. */
    @Volatile
    private var generation = 0

    /** False while the app is in the background: no polling then. */
    val foreground = MutableStateFlow(true)

    /** Called when an automation asks to open the chat and none is on screen. */
    var onOpenRequested: (() -> Unit)? = null

    /** Set by Hollo.onPushPermission: returns the FCM token, or null. */
    var pushPermission: (suspend () -> String?)? = null

    /** Whether the system permission prompt can still be shown (set by Hollo). */
    var canAskPermission: () -> Boolean = { false }

    val isStarted: Boolean get() = client != null
    val isChatVisible: Boolean get() = visibleChats.get() > 0

    private inline fun mutate(change: (HolloState) -> HolloState) {
        _state.update(change)
        _unread.value = _state.value.unread
    }

    private fun api(): HolloClient =
        client ?: throw IllegalStateException("Call Hollo.start(context, appKey) before using Hollo.")

    /** [pushToken] is a token set before start ([hasPushToken] tells null apart from "none"). */
    fun start(client: HolloClient, hasPushToken: Boolean, pushToken: String?) {
        this.client = client
        generation++
        mutate { HolloState(started = true, open = it.open) }
        poller?.cancel()
        poller = scope.launch {
            // Re-send the saved token at each launch: cheap, and it heals a
            // token that failed to save or belongs to a replaced device.
            val token = if (hasPushToken) pushToken else client.getValue(PUSH_TOKEN)
            if (hasPushToken || token != null) ignoreErrors { registerPush(token) }
            pollLoop()
        }
    }

    private suspend fun pollLoop() {
        while (true) {
            foreground.first { it }
            refreshOnce()
            val wait = if (_state.value.open) OPEN_POLL_MS else CLOSED_POLL_MS
            withTimeoutOrNull(wait) { wake.receive() }
        }
    }

    /** Polls now instead of waiting for the next tick. */
    fun refresh() {
        wake.trySend(Unit)
    }

    private suspend fun refreshOnce() {
        val api = client ?: return
        val startedAt = generation
        try {
            val after = _state.value.messages.lastOrNull()?.createdAt
            val response = api.messages(after)
            if (startedAt != generation) return
            if (response.open && !_state.value.open) onOpenRequested?.invoke()
            mutate { s ->
                val known = s.messages.mapTo(HashSet()) { it.id }
                s.copy(
                    messages = s.messages + response.messages.filter { it.id !in known },
                    profile = response.profile ?: s.profile,
                    push = response.push ?: s.push,
                    branding = response.branding,
                    unread = if (s.open) 0 else response.unread,
                    error = null,
                    offline = false,
                )
            }
            if (_state.value.open && response.unread > 0) ignoreErrors { api.markRead() }
            if (_state.value.pending.isNotEmpty()) flush()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            mutate { it.copy(error = e.message ?: "Couldn't reach Hollo.", offline = isOffline(e)) }
        }
    }

    fun chatShown() {
        if (visibleChats.incrementAndGet() == 1) setOpen(true)
    }

    fun chatHidden() {
        if (visibleChats.decrementAndGet() <= 0) {
            visibleChats.set(0)
            setOpen(false)
        }
    }

    private fun setOpen(open: Boolean) {
        mutate { it.copy(open = open, unread = if (open) 0 else it.unread) }
        if (open && client != null) scope.launch { ignoreErrors { client?.markRead() } }
        refresh()
    }

    /**
     * Queues the message and sends it. If the phone is offline it stays in
     * the queue and goes out with the next successful poll. [onRejected]
     * gets the text back when the server refused it, so the UI can restore it.
     */
    fun send(text: String, onRejected: (String) -> Unit) {
        val body = text.trim()
        if (body.isEmpty()) return
        if (client == null) {
            mutate { it.copy(error = "Call Hollo.start(context, appKey) before using Hollo.") }
            onRejected(body)
            return
        }
        val item = PendingMessage(UUID.randomUUID().toString(), body)
        val first = _state.value.messages.none { it.sender == Sender.END_USER }
        mutate { it.copy(pending = it.pending + item) }
        scope.launch {
            flush()
            if (rejected.remove(item.localId) != null) {
                onRejected(body)
                return@launch
            }
            val delivered = _state.value.pending.none { it.localId == item.localId }
            if (first && delivered) maybeAskForPush()
        }
    }

    /** Sends queued messages in order; stops at the first network failure. */
    private suspend fun flush() {
        sendLock.withLock {
            while (true) {
                val api = client ?: return
                val next = _state.value.pending.firstOrNull() ?: return
                try {
                    val message = api.send(next.body)
                    mutate { s ->
                        s.copy(
                            pending = s.pending.filterNot { it.localId == next.localId },
                            messages = if (s.messages.any { it.id == message.id }) s.messages else s.messages + message,
                            error = null,
                            offline = false,
                        )
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    if (isOffline(e)) {
                        mutate { it.copy(offline = true, error = e.message) }
                        return
                    }
                    // Refused (too long, plan ended...): sending again won't help.
                    rejected[next.localId] = e
                    mutate { s ->
                        s.copy(pending = s.pending.filterNot { it.localId == next.localId }, error = e.message)
                    }
                }
            }
        }
    }

    /** Reports an event; automations may open the chat in response. */
    suspend fun track(name: String) {
        val open = api().event(name = name)
        if (open && !_state.value.open) onOpenRequested?.invoke() else refresh()
    }

    suspend fun setSubscriber(subscriber: Boolean) {
        api().event(subscriber = subscriber)
    }

    /** Saves the push token, or null when the user turns notifications off. */
    suspend fun registerPush(token: String?) {
        val api = api()
        // Saved first, so a failed request is retried at the next launch.
        if (token == null) api.removeValue(PUSH_TOKEN) else api.setValue(PUSH_TOKEN, token)
        api.registerPush(token)
        mutate { it.copy(pushRegistered = token != null, askPush = false) }
    }

    /** Just after the first message: the moment a reply is worth waiting for. */
    private suspend fun maybeAskForPush() {
        val s = _state.value
        if (s.push.permissionCard == "off" || s.pushRegistered) return
        if (pushPermission == null || !canAskPermission()) return
        if (api().getValue(PUSH_ASKED) != null) return
        mutate { it.copy(askPush = true) }
    }

    /** The user answered the card, after the system prompt. Either way it never shows again. */
    fun answerPushCard(accept: Boolean) {
        mutate { it.copy(askPush = false) }
        scope.launch {
            ignoreErrors { client?.setValue(PUSH_ASKED, "1") }
            val handler = pushPermission
            if (!accept || handler == null) return@launch
            val token = try {
                handler()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            if (token != null) ignoreErrors { registerPush(token) }
        }
    }

    suspend fun identify(id: String, name: String?, email: String?, identityToken: String?) {
        accountLock.withLock {
            api().identify(id, name, email, identityToken)
            reload(clearPending = false)
        }
    }

    /** Signing out starts a fresh anonymous chat; history stays on the server. */
    suspend fun signOut() {
        accountLock.withLock {
            api().forgetDevice()
            reload(clearPending = true)
        }
    }

    /** Deletes this user's support data (account-deletion rules). */
    suspend fun eraseUserData() {
        accountLock.withLock {
            api().eraseUserData()
            reload(clearPending = true)
        }
    }

    /** Reports a link card tap for the dashboard's counts. Never throws. */
    fun linkTapped(messageId: String, opened: Boolean) {
        scope.launch { ignoreErrors { client?.linkTapped(messageId, opened) } }
    }

    private suspend fun reload(clearPending: Boolean) {
        generation++
        mutate {
            it.copy(
                messages = emptyList(),
                pending = if (clearPending) emptyList() else it.pending,
                unread = 0,
                pushRegistered = false,
                askPush = false,
            )
        }
        // Signing out makes a new device, so it needs the push token again.
        val api = api()
        val token = api.getValue(PUSH_TOKEN)
        if (token != null) ignoreErrors { registerPush(token) }
        refresh()
    }

    private fun isOffline(e: Exception) = e is HolloException && e.status == 0

    private inline fun ignoreErrors(block: () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Best effort: the next poll or launch tries again.
        }
    }
}
