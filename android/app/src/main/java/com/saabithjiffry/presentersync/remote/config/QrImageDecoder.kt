package com.saabithjiffry.presentersync.remote.config

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.camera.core.ImageProxy
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.LuminanceSource
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.GlobalHistogramBinarizer
import com.google.zxing.common.HybridBinarizer

/**
 * Resilient offline QR decoder for both live CameraX YUV frames and gallery-imported images.
 * Handles arbitrary YUV rowStride/pixelStride padding, inverted contrast, and high-res bitmap
 * downsampling safely without risking OOM or IllegalArgumentException on diverse OEM chipsets.
 */
object QrImageDecoder {

    private const val MAX_BITMAP_DIM = 1600

    fun createQrReader(): MultiFormatReader = MultiFormatReader().apply {
        setHints(
            mapOf(
                DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE),
                DecodeHintType.TRY_HARDER to true,
                DecodeHintType.ALSO_INVERTED to true
            )
        )
    }

    /**
     * Extracts a tightly packed single-channel Y luminance buffer from an [ImageProxy] and
     * attempts QR decode with HybridBinarizer followed by GlobalHistogramBinarizer.
     */
    fun decodeImageProxy(image: ImageProxy, reader: MultiFormatReader): String? {
        val plane = image.planes.firstOrNull() ?: return null
        val w = image.width
        val h = image.height
        if (w <= 0 || h <= 0) return null

        val yBytes = extractTightYPlane(
            buffer = plane.buffer,
            width = w,
            height = h,
            rowStride = plane.rowStride,
            pixelStride = plane.pixelStride
        ) ?: return null

        val source = PlanarYUVLuminanceSource(yBytes, w, h, 0, 0, w, h, false)
        return decodeLuminanceSource(source, reader)
    }

    /**
     * Decodes a gallery/document [Uri] by safely downsampling to <= [MAX_BITMAP_DIM]px.
     */
    fun decodeUri(context: Context, uri: Uri): String? {
        val resolver = context.contentResolver
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        } ?: return null

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sampleSize = 1
        var maxSide = maxOf(bounds.outWidth, bounds.outHeight)
        while (maxSide / 2 >= MAX_BITMAP_DIM) {
            sampleSize *= 2
            maxSide /= 2
        }

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val bitmap = resolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, decodeOpts)
        } ?: return null

        return try {
            decodeBitmap(bitmap)
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
    }

    /**
     * Decodes an in-memory [Bitmap] using ZXing HybridBinarizer and GlobalHistogramBinarizer.
     */
    fun decodeBitmap(bitmap: Bitmap): String? {
        val w = bitmap.width
        val h = bitmap.height
        if (w <= 0 || h <= 0) return null
        val pixels = IntArray(w * h)
        bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
        val source = RGBLuminanceSource(w, h, pixels)
        val reader = createQrReader()
        return decodeLuminanceSource(source, reader)
    }

    /**
     * Extracts tight [width]x[height] Y bytes regardless of HAL [rowStride] or [pixelStride].
     */
    internal fun extractTightYPlane(
        buffer: java.nio.ByteBuffer,
        width: Int,
        height: Int,
        rowStride: Int,
        pixelStride: Int
    ): ByteArray? {
        if (width <= 0 || height <= 0 || rowStride < width || pixelStride < 1) return null
        val dup = buffer.duplicate()
        dup.rewind()
        val remaining = dup.remaining()
        val out = ByteArray(width * height)

        if (pixelStride == 1 && rowStride == width && remaining >= out.size) {
            dup.get(out, 0, out.size)
            return out
        }

        val rowBuf = ByteArray(rowStride)
        for (row in 0 until height) {
            val rowStart = row * rowStride
            if (rowStart >= remaining) break
            val available = minOf(rowStride, remaining - rowStart)
            dup.position(rowStart)
            dup.get(rowBuf, 0, available)
            if (pixelStride == 1) {
                val copyLen = minOf(width, available)
                System.arraycopy(rowBuf, 0, out, row * width, copyLen)
            } else {
                val outRowOffset = row * width
                for (col in 0 until width) {
                    val idx = col * pixelStride
                    if (idx < available) {
                        out[outRowOffset + col] = rowBuf[idx]
                    }
                }
            }
        }
        return out
    }

    private fun decodeLuminanceSource(source: LuminanceSource, reader: MultiFormatReader): String? {
        try {
            reader.reset()
            return reader.decodeWithState(BinaryBitmap(HybridBinarizer(source)))?.text?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            // Fall through to GlobalHistogramBinarizer for low-contrast / uneven illumination
        }
        return try {
            reader.reset()
            reader.decodeWithState(BinaryBitmap(GlobalHistogramBinarizer(source)))?.text?.trim()?.takeIf { it.isNotEmpty() }
        } catch (_: Exception) {
            null
        } finally {
            reader.reset()
        }
    }
}
