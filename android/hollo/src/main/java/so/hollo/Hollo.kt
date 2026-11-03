package so.hollo

import android.app.Activity
import android.app.Application
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import java.lang.ref.WeakReference
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/**
 * Hollo's public API: start it once in your Application, then open the chat
 * with [present] or the [HolloChat] composable.
 */
object Hollo {
    internal const val SDK_VERSION = "0.1.4"
    private const val TAG = "Hollo"
    private const val PREFS = "so.hollo"
    private const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
    private val APP_KEY = Regex("^app_[0-9a-f]{32}$")

    // Main-thread scope: state changes and callbacks happen on the UI thread,
    // network and storage hop to IO inside the client. Failures are logged
    // (without message text or personal details), never thrown into the app.
    internal val scope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main.immediate +
            CoroutineExceptionHandler { _, e -> Log.w(TAG, "Background task failed: ${describe(e)}") },
    )
    internal val store = HolloStore(scope)

    @Volatile
    private var appContext: Context? = null
    private var resumed: WeakReference<Activity>? = null
    private var chatActivity: WeakReference<HolloChatActivity>? = null
    private var startedActivities = 0
    private var callbacksRegistered = false
    private var offerHandler: ((HolloOffer) -> Unit)? = null
    private var linkHandler: ((HolloLink) -> Unit)? = null

    private class PendingPush(val token: String?)

    @Volatile
    private var pendingPush: PendingPush? = null

    /** How the chat looks. Set it before the chat opens. */
    @JvmStatic
    var theme: HolloTheme = HolloTheme()

    /** Replies the user hasn't seen, for your Support badge. Updates live. */
    @JvmStatic
    val unreadCount: StateFlow<Int> = store.unread

    init {
        store.onOpenRequested = { openFromServer() }
        store.canAskPermission = { canAskForNotifications() }
    }

    /**
     * Call once when your app process starts, in Application.onCreate. It's
     * quick, shows nothing and asks the user for nothing.
     *
     * @param apiUrl only for testing against a local server.
     */
    @JvmStatic
    @JvmOverloads
    fun start(context: Context, appKey: String, apiUrl: String = DEFAULT_API_URL) {
        val app = context.applicationContext ?: context
        appContext = app
        if (!APP_KEY.matches(appKey)) {
            Log.w(TAG, "That doesn't look like a Hollo app key. Copy it from your dashboard (it starts with app_).")
        }
        if (app is Application && !callbacksRegistered) {
            app.registerActivityLifecycleCallbacks(lifecycle)
            callbacksRegistered = true
            // Started from an activity rather than the Application: count it.
            if (context is Activity) {
                startedActivities = 1
                resumed = WeakReference(context)
            }
        }
        val client = HolloClient(
            appKey = appKey,
            apiUrl = apiUrl,
            storage = SharedPreferencesStorage(app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)),
            platform = "android",
            info = deviceInfo(app),
        )
        val push = pendingPush
        pendingPush = null
        store.start(client, hasPushToken = push != null, pushToken = push?.token)
    }

    /** Opens the support chat as its own screen. The back button closes it. */
    @JvmStatic
    fun present(context: Context) {
        val intent = Intent(context, HolloChatActivity::class.java)
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** Closes the chat opened with [present]. */
    @JvmStatic
    fun dismiss() {
        scope.launch { chatActivity?.get()?.finish() }
    }

    /**
     * Links this device to your app's user, so history follows them. Pass
     * [identityToken] (an HMAC-SHA256 of [id], made by your server with the
     * app's identity secret) to mark the user as verified.
     */
    @JvmStatic
    @JvmOverloads
    fun identify(id: String, name: String? = null, email: String? = null, identityToken: String? = null) {
        background("identify") { store.identify(id, name, email, identityToken) }
    }

    /** Starts a fresh anonymous chat. The history stays in your inbox. */
    @JvmStatic
    fun signOut() {
        background("signOut") { store.signOut() }
    }

    /**
     * Deletes the user's conversation and details from Hollo and clears them
     * from the device, for account-deletion flows. Can't be undone. Throws
     * [HolloException] if it fails, so you can let the user try again.
     */
    suspend fun eraseUserData() {
        store.eraseUserData()
    }

    /**
     * Runs when the user taps an offer the team sent. The chat closes first;
     * open your paywall or apply the discount for [HolloOffer.ref] here.
     */
    @JvmStatic
    fun onOffer(handler: (HolloOffer) -> Unit) {
        offerHandler = handler
    }

    /**
     * Runs when the user taps a link card that opens one of your screens. The
     * chat closes first; navigate to [HolloLink.screen] here.
     */
    @JvmStatic
    fun onLink(handler: (HolloLink) -> Unit) {
        linkHandler = handler
    }

    /**
     * Reports something the user did, like "paywall_declined". Automations set
     * up in the dashboard can reply, send an offer or open the chat.
     */
    @JvmStatic
    fun track(event: String) {
        background("track") { store.track(event) }
    }

    /** Tells Hollo whether the user pays, for automation audiences and the AI. */
    @JvmStatic
    fun setSubscriber(isSubscriber: Boolean) {
        background("setSubscriber") { store.setSubscriber(isSubscriber) }
    }

    /**
     * Saves the device's FCM token, so replies reach the user when the chat is
     * closed. Call it from FirebaseMessagingService.onNewToken, and pass null
     * if the user turns notifications off. Safe to call before [start].
     */
    @JvmStatic
    fun registerPush(token: String?) {
        val value = token?.trim()?.takeIf { it.isNotEmpty() }
        scope.launch {
            if (!store.isStarted) {
                pendingPush = PendingPush(value)
                return@launch
            }
            try {
                store.registerPush(value)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Couldn't save the push token: ${describe(e)}")
            }
        }
    }

    /** True if this push (its data map) came from Hollo. */
    @JvmStatic
    fun isHolloNotification(data: Map<String, String>): Boolean = data["hollo"] == "true"

    /**
     * Call from FirebaseMessagingService.onMessageReceived. Returns true if the
     * message was Hollo's, so your own notifications still reach your code.
     * FCM only calls onMessageReceived while your app is in the foreground,
     * so Hollo fetches the reply right away (the chat and the unread badge
     * update) instead of covering the screen the user is on.
     *
     * Firebase is a compile-only dependency: your app brings its own.
     */
    @JvmStatic
    fun handle(message: RemoteMessage): Boolean = handle(message.data)

    /** The same as handle(RemoteMessage), for the message's data map. */
    @JvmStatic
    fun handle(data: Map<String, String>): Boolean {
        if (!isHolloNotification(data)) return false
        store.refresh()
        return true
    }

    /**
     * For the activity a tapped notification launched (FCM puts the data in
     * its extras when your app was in the background). Call it from onCreate
     * and onNewIntent. Returns true and opens the chat if it was Hollo's.
     */
    @JvmStatic
    fun handle(intent: Intent?): Boolean {
        if (intent == null) return false
        val extras = intent.extras ?: return false
        if (extras.getString("hollo") != "true") return false
        // So a rotation or relaunch doesn't open the chat again.
        intent.removeExtra("hollo")
        openSoon()
        return true
    }

    /**
     * Lets the chat offer notifications after the user's first message, when
     * the permission card is on in the dashboard. Hollo shows the system
     * prompt when the user taps Continue; return the FCM token here (for
     * example FirebaseMessaging.getInstance().token.await()), or null.
     */
    @JvmStatic
    fun onPushPermission(handler: suspend () -> String?) {
        store.pushPermission = handler
    }

    // Internal: what the chat screen calls.

    internal fun chatCreated(activity: HolloChatActivity) {
        chatActivity = WeakReference(activity)
    }

    internal fun chatDestroyed(activity: HolloChatActivity) {
        if (chatActivity?.get() === activity) chatActivity = null
    }

    internal fun tapOffer(offer: HolloOffer) {
        dismiss()
        offerHandler?.invoke(offer)
    }

    /** Links open a URL themselves; screens go to the app's onLink handler. */
    internal fun tapLink(context: Context, message: HolloMessage) {
        when (val action = linkAction(message.payload)) {
            is LinkAction.Url -> store.linkTapped(message.id, openUrl(context, action.url))
            is LinkAction.Screen -> {
                val handler = linkHandler
                if (handler != null) {
                    dismiss()
                    handler(HolloLink(action.screen, action.value))
                }
                store.linkTapped(message.id, handler != null)
            }
            null -> store.linkTapped(message.id, false)
        }
    }

    internal fun tapReview(context: Context, payload: Map<String, String>) {
        val url = reviewUrl("android", payload) ?: return
        // No Play Store app (some emulators and Huawei phones): use the web page.
        if (!openUrl(context, url)) playStoreWebUrl(payload)?.let { openUrl(context, it) }
    }

    internal fun openUrl(context: Context, url: String): Boolean =
        try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }

    internal fun canAskForNotifications(): Boolean {
        // Below Android 13 there's no prompt to show; the card would be noise.
        if (Build.VERSION.SDK_INT < 33) return false
        val context = appContext ?: return false
        return context.checkSelfPermission(POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    }

    internal fun needsNotificationPrompt(context: Context): Boolean =
        Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED

    internal const val NOTIFICATION_PERMISSION = POST_NOTIFICATIONS

    private fun openSoon() {
        scope.launch {
            store.refresh()
            if (store.isChatVisible) return@launch
            val context = resumed?.get() ?: appContext ?: return@launch
            present(context)
        }
    }

    /** An automation asked to open the chat: only over a screen the user is looking at. */
    private fun openFromServer() {
        val activity = resumed?.get() ?: return
        if (activity is HolloChatActivity || store.isChatVisible) return
        present(activity)
    }

    private fun background(what: String, block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "$what failed: ${describe(e)}")
            }
        }
    }

    private fun describe(e: Throwable) =
        if (e is HolloException) "${e.code} (${e.status})" else e.javaClass.simpleName

    private fun deviceInfo(context: Context): Map<String, String> {
        val info = linkedMapOf(
            "os" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
            // Review requests and other team messages use it to pick wording.
            "language" to Locale.getDefault().toLanguageTag(),
            "sdk" to "android $SDK_VERSION",
        )
        appVersion(context)?.let { info["app"] = it }
        return info
    }

    private fun appVersion(context: Context): String? =
        try {
            val manager = context.packageManager
            if (Build.VERSION.SDK_INT >= 33) {
                manager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0)).versionName
            } else {
                legacyPackageInfo(manager, context.packageName)
            }
        } catch (e: Exception) {
            null
        }

    @Suppress("DEPRECATION")
    private fun legacyPackageInfo(manager: PackageManager, name: String): String? =
        manager.getPackageInfo(name, 0).versionName

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

        override fun onActivityStarted(activity: Activity) {
            startedActivities++
            store.foreground.value = true
        }

        override fun onActivityResumed(activity: Activity) {
            resumed = WeakReference(activity)
        }

        override fun onActivityPaused(activity: Activity) {
            if (resumed?.get() === activity) resumed = null
        }

        override fun onActivityStopped(activity: Activity) {
            startedActivities = (startedActivities - 1).coerceAtLeast(0)
            if (startedActivities == 0) store.foreground.value = false
        }

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

        override fun onActivityDestroyed(activity: Activity) {}
    }
}
