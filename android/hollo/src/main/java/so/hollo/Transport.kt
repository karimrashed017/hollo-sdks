package so.hollo

import android.content.SharedPreferences
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

// The two things the client needs from the platform, behind small interfaces
// so the client can be unit-tested on the plain JVM with fakes.

internal data class HolloHttpRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
    val body: String?,
)

internal data class HolloHttpResponse(val status: Int, val body: String)

internal fun interface HolloTransport {
    /** Blocking. Throws IOException when the server can't be reached. */
    @Throws(IOException::class)
    fun execute(request: HolloHttpRequest): HolloHttpResponse
}

/** HttpURLConnection, so Hollo adds no HTTP library to the app. */
internal class HttpUrlConnectionTransport(
    private val timeoutMs: Int = 15_000,
) : HolloTransport {
    override fun execute(request: HolloHttpRequest): HolloHttpResponse {
        val connection = URL(request.url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = request.method
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            connection.useCaches = false
            for ((name, value) in request.headers) connection.setRequestProperty(name, value)
            if (request.body != null) {
                val bytes = request.body.toByteArray(Charsets.UTF_8)
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.outputStream.use { it.write(bytes) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            return HolloHttpResponse(status, text)
        } finally {
            connection.disconnect()
        }
    }
}

/** Key-value storage for the device token and a few flags. */
internal interface HolloStorage {
    fun get(key: String): String?

    fun set(key: String, value: String)

    fun remove(key: String)
}

internal class SharedPreferencesStorage(private val prefs: SharedPreferences) : HolloStorage {
    override fun get(key: String): String? = prefs.getString(key, null)

    // commit, not apply: callers are already off the main thread, and a
    // token that's lost on a crash would orphan the conversation.
    override fun set(key: String, value: String) {
        prefs.edit().putString(key, value).commit()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).commit()
    }
}
