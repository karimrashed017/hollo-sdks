package so.hollo

import java.io.IOException
import java.net.URLEncoder
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

// The Hollo HTTP client: no Android UI, so it can be unit-tested. Talks to the
// SDK API at https://hollo.so/api/v1 with the app key and this install's
// device token, mirroring the React Native SDK's client.

internal const val DEFAULT_API_URL = "https://hollo.so/api/v1"

internal class HolloClient(
    val appKey: String,
    apiUrl: String = DEFAULT_API_URL,
    private val storage: HolloStorage,
    private val platform: String = "android",
    private val info: Map<String, String> = emptyMap(),
    private val transport: HolloTransport = HttpUrlConnectionTransport(),
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val apiUrl = apiUrl.trimEnd('/')
    private val tokenLock = Mutex()

    @Volatile
    private var token: String? = null

    private val tokenKey = "hollo.deviceToken.$appKey"

    /** The device token, registering this install the first time. */
    private suspend fun deviceToken(): String =
        tokenLock.withLock {
            token ?: (read(tokenKey) ?: register()).also { token = it }
        }

    private suspend fun register(): String {
        val body = buildJsonObject {
            put("platform", platform)
            putJsonObject("info") {
                for ((key, value) in info) put(key, value)
            }
        }
        val data = call("/devices", method = "POST", body = body, auth = false)
        val newToken = data.string("deviceToken")
            ?: throw HolloException("invalid_response", "No device token in the response.", 201)
        write(tokenKey, newToken)
        return newToken
    }

    private suspend fun call(
        path: String,
        method: String = "GET",
        body: JsonObject? = null,
        auth: Boolean = true,
        retried: Boolean = false,
    ): JsonObject {
        val headers = linkedMapOf(
            "x-hollo-app-key" to appKey,
            "accept" to "application/json",
        )
        // Some HTTP stacks refuse a POST without a body, so send "{}".
        val payload = body ?: if (method == "POST") JsonObject(emptyMap()) else null
        if (payload != null) headers["content-type"] = "application/json"
        val used = if (auth) deviceToken() else null
        if (used != null) headers["authorization"] = "Bearer $used"

        val response = try {
            withContext(io) {
                transport.execute(HolloHttpRequest(method, apiUrl + path, headers, payload?.toString()))
            }
        } catch (e: IOException) {
            throw HolloException("network_error", "Couldn't reach Hollo. Check the connection.", 0, e)
        }

        val data = parseObject(response.body)
        if (response.status in 200..299) return data

        val error = data["error"] as? JsonObject
        val code = error?.string("code") ?: "network_error"
        // The server forgot this device (e.g. its data was erased): register again.
        if (code == "invalid_device" && used != null && !retried) {
            forgetDevice(used)
            return call(path, method, body, auth, retried = true)
        }
        throw HolloException(
            code,
            error?.string("message") ?: "Request failed (${response.status})",
            response.status,
        )
    }

    /** Forgets the device token, so the next call registers a new device. */
    suspend fun forgetDevice() {
        tokenLock.withLock {
            token = null
            remove(tokenKey)
        }
    }

    /** Only forgets [used] if no other call has replaced it in the meantime. */
    private suspend fun forgetDevice(used: String) {
        tokenLock.withLock {
            if (token == null || token == used) {
                token = null
                remove(tokenKey)
            }
        }
    }

    /** A missing `verified` (an older server) counts as not verified. */
    data class Identified(val userId: String?, val verified: Boolean)

    suspend fun identify(id: String, name: String?, email: String?, identityToken: String? = null): Identified {
        val body = buildJsonObject {
            put("id", id)
            if (name != null) put("name", name)
            if (email != null) put("email", email)
            if (identityToken != null) put("token", identityToken)
        }
        val data = call("/identify", method = "POST", body = body)
        val verified = data["verified"] as? JsonPrimitive
        return Identified(data.string("userId"), verified?.booleanOrNull == true)
    }

    suspend fun messages(after: String? = null): MessagesResponse {
        val query = if (after.isNullOrEmpty()) "" else "?after=" + URLEncoder.encode(after, "UTF-8")
        return parseMessagesResponse(call("/messages$query"))
    }

    suspend fun send(body: String): HolloMessage {
        val data = call("/messages", method = "POST", body = buildJsonObject { put("body", body) })
        return data["message"]?.let { parseMessage(it) }
            ?: throw HolloException("invalid_response", "No message in the response.", 201)
    }

    /** Counts a link card tap; [opened] is false when nothing could open it. */
    suspend fun linkTapped(messageId: String, opened: Boolean) {
        call(
            "/links/tap",
            method = "POST",
            body = buildJsonObject {
                put("messageId", messageId)
                put("opened", opened)
            },
        )
    }

    /** Reports an event or the subscription status. Returns whether to open the chat. */
    suspend fun event(name: String? = null, subscriber: Boolean? = null): Boolean {
        val body = buildJsonObject {
            if (name != null) put("name", name)
            if (subscriber != null) put("subscriber", subscriber)
        }
        val open = call("/events", method = "POST", body = body)["open"] as? JsonPrimitive
        return open?.booleanOrNull == true
    }

    /** Saves the FCM token, or null to stop notifications. */
    suspend fun registerPush(token: String?) {
        call(
            "/push",
            method = "POST",
            body = buildJsonObject {
                put("token", token)
                put("provider", "fcm")
            },
        )
    }

    suspend fun markRead() {
        call("/read", method = "POST")
    }

    suspend fun eraseUserData() {
        call("/user", method = "DELETE")
        forgetDevice()
    }

    // Small values kept beside the device token, like "asked for push".
    suspend fun getValue(name: String): String? = read(valueKey(name))

    suspend fun setValue(name: String, value: String) = write(valueKey(name), value)

    suspend fun removeValue(name: String) = remove(valueKey(name))

    private fun valueKey(name: String) = "hollo.$name.$appKey"

    private suspend fun read(key: String): String? = withContext(io) { storage.get(key) }

    private suspend fun write(key: String, value: String) {
        withContext(io) { storage.set(key, value) }
    }

    private suspend fun remove(key: String) {
        withContext(io) { storage.remove(key) }
    }
}
