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

// The chat shows the profile photo and the photos in messages, so a tiny
// loader beats adding an image library to every app that uses Hollo.

// Counted in bytes, not images: one full-screen photo weighs as much as
// hundreds of avatars.
private val cache = object : LruCache<String, ImageBitmap>(
    (Runtime.getRuntime().maxMemory() / 8).coerceAtMost(32L * 1024 * 1024).toInt(),
) {
    override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
}

/**
 * The image at [url], or null while it loads or if it can't. A [maxEdge]
 * above 0 decodes it smaller (by powers of two), for thumbnails.
 */
@Composable
internal fun rememberRemoteImage(url: String?, maxEdge: Int = 0): ImageBitmap? {
    val key = url?.let { "$it@$maxEdge" }
    val image = produceState<ImageBitmap?>(initialValue = key?.let { cache.get(it) }, key) {
        // produceState keeps the last value when the key changes, so look again.
        value = key?.let { cache.get(it) }
        if (url == null || key == null || value != null) return@produceState
        value = withContext(Dispatchers.IO) { download(url, maxEdge) }?.also { cache.put(key, it) }
    }
    return image.value
}

private fun download(url: String, maxEdge: Int): ImageBitmap? =
    try {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            if (connection.responseCode != 200) {
                null
            } else {
                val bytes = connection.inputStream.use { it.readBytes() }
                decodeSampled(bytes, maxEdge)?.asImageBitmap()
            }
        } finally {
            connection.disconnect()
        }
    } catch (e: Exception) {
        null
    } catch (e: OutOfMemoryError) {
        null
    }

private fun decodeSampled(bytes: ByteArray, maxEdge: Int) =
    if (maxEdge <= 0) {
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } else {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }
