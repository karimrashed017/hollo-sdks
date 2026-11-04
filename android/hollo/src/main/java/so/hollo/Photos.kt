package so.hollo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// Photos the user attaches (F-17): picked with the system photo picker, then
// shrunk on the phone so an upload is a few hundred KB, not a 12 MP original.

internal const val KIND_IMAGE = "image"

/** The most photos one message can carry. */
internal const val MAX_PHOTOS = 5

/** The server refuses anything bigger; a 1600 px JPEG stays far below it. */
internal const val PHOTO_MAX_BYTES = 4 * 1024 * 1024

private const val PHOTO_MAX_EDGE = 1600
private const val PHOTO_QUALITY = 70
private const val THUMBNAIL_EDGE = 256

/** The biggest power-of-two step down that still leaves the long edge at least [maxEdge]. */
internal fun sampleSize(width: Int, height: Int, maxEdge: Int): Int {
    if (maxEdge <= 0) return 1
    val longEdge = maxOf(width, height)
    var sample = 1
    while (longEdge / (sample * 2) >= maxEdge) sample *= 2
    return sample
}

/** [width] × [height] shrunk so the long edge is at most [maxEdge]. Never enlarged. */
internal fun fitWithin(width: Int, height: Int, maxEdge: Int): Pair<Int, Int> {
    val longEdge = maxOf(width, height)
    if (longEdge <= maxEdge || longEdge <= 0) return width to height
    val scale = maxEdge.toDouble() / longEdge
    return maxOf(1, (width * scale).roundToInt()) to maxOf(1, (height * scale).roundToInt())
}

/**
 * The picked photo, upright and with its long edge at most [maxEdge], or
 * null if it can't be read. Blocking: call it off the main thread.
 */
internal fun decodePhoto(context: Context, uri: Uri, maxEdge: Int): Bitmap? {
    val resolver = context.contentResolver
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    // A bounds-only decode always returns null, so only a missing stream means failure.
    val stream = resolver.openInputStream(uri) ?: return null
    stream.use { BitmapFactory.decodeStream(it, null, bounds) }
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    // Decoding at a power-of-two step first keeps a 50 MP photo from filling memory.
    val options = BitmapFactory.Options().apply {
        inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
    }
    val decoded = resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) } ?: return null
    // BitmapFactory ignores EXIF, so a portrait phone photo would arrive sideways.
    val orientation = try {
        resolver.openInputStream(uri)?.use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }
    } catch (e: Exception) {
        null
    } ?: ExifInterface.ORIENTATION_NORMAL
    val matrix = orientationMatrix(orientation)
    val (width, _) = fitWithin(decoded.width, decoded.height, maxEdge)
    val scale = width.toFloat() / decoded.width
    if (scale < 1f) matrix.postScale(scale, scale)
    if (matrix.isIdentity) return decoded
    val upright = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    if (upright !== decoded) decoded.recycle()
    return upright
}

private fun orientationMatrix(orientation: Int): Matrix = Matrix().apply {
    when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
            setRotate(180f)
            postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_TRANSPOSE -> {
            setRotate(90f)
            postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE -> {
            setRotate(-90f)
            postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
    }
}

/** The picked photo as a JPEG ready for [HolloClient.uploadPhoto]. Runs on IO. */
internal suspend fun compressPhoto(context: Context, uri: Uri): ByteArray = withContext(Dispatchers.IO) {
    val bitmap = try {
        decodePhoto(context, uri, PHOTO_MAX_EDGE)
    } catch (e: OutOfMemoryError) {
        null
    } ?: throw HolloException("unsupported_photo", "Couldn't read that photo.", 415)
    try {
        // JPEG has no transparency: a PNG's clear parts would turn black, so put them on white.
        val opaque = if (bitmap.hasAlpha()) onWhite(bitmap) else bitmap
        try {
            var quality = PHOTO_QUALITY
            var bytes = encodeJpeg(opaque, quality)
            while (bytes.size > PHOTO_MAX_BYTES && quality > 30) {
                quality -= 15
                bytes = encodeJpeg(opaque, quality)
            }
            if (bytes.size > PHOTO_MAX_BYTES) {
                throw HolloException("photo_too_large", "Photos can be up to 4 MB.", 413)
            }
            bytes
        } finally {
            if (opaque !== bitmap) opaque.recycle()
        }
    } finally {
        bitmap.recycle()
    }
}

private fun onWhite(bitmap: Bitmap): Bitmap {
    val flat = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
    Canvas(flat).apply {
        drawColor(Color.WHITE)
        drawBitmap(bitmap, 0f, 0f, null)
    }
    return flat
}

private fun encodeJpeg(bitmap: Bitmap, quality: Int): ByteArray {
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
    return out.toByteArray()
}

/** A small preview of a picked photo for the composer, or null while it loads. */
@Composable
internal fun rememberPickedPhoto(uri: Uri): ImageBitmap? {
    val context = LocalContext.current.applicationContext
    val image = produceState<ImageBitmap?>(initialValue = null, uri) {
        value = withContext(Dispatchers.IO) {
            try {
                decodePhoto(context, uri, THUMBNAIL_EDGE)?.asImageBitmap()
            } catch (e: Exception) {
                // The picker's read grant can lapse (after process death, say).
                null
            }
        }
    }
    return image.value
}
