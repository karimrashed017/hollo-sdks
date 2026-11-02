package so.hollo

import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// The profile photo is the only image the chat shows, so a tiny loader beats
// adding an image library to every app that uses Hollo.

private val cache = LruCache<String, ImageBitmap>(8)

@Composable
internal fun rememberRemoteImage(url: String?): ImageBitmap? {
    val image = produceState<ImageBitmap?>(initialValue = url?.let { cache.get(it) }, url) {
        if (url == null || value != null) return@produceState
        value = withContext(Dispatchers.IO) { download(url) }
    }
    return image.value
}

private fun download(url: String): ImageBitmap? =
    try {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            if (connection.responseCode != 200) {
                null
            } else {
                connection.inputStream.use { BitmapFactory.decodeStream(it) }
                    ?.asImageBitmap()
                    ?.also { cache.put(url, it) }
            }
        } finally {
            connection.disconnect()
        }
    } catch (e: Exception) {
        null
    }
