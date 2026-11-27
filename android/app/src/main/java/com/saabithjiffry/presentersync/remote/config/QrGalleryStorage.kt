package com.saabithjiffry.presentersync.remote.config

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Generates high-resolution (1024x1024, ISO 4-module quiet zone) PresenterSync pairing QR PNGs
 * and saves them cleanly to the Android photo gallery via scoped MediaStore (API 29+) or
 * user-selected document output (API 26-28).
 */
object QrGalleryStorage {

    const val DEFAULT_QR_SIZE_PX = 1024
    const val ISO_QUIET_ZONE_MODULES = 4

    sealed class SaveResult {
        data class SavedToGallery(val displayName: String, val uri: Uri) : SaveResult()
        data class RequiresDocumentPicker(val suggestedName: String, val pngBytes: ByteArray) : SaveResult()
        data class Failed(val reason: String) : SaveResult()
    }

    /**
     * Renders a crisp, unblurred 1024x1024 black-on-white QR PNG with a 4-module quiet zone.
     */
    fun encodeQrPngBytes(payload: String, sizePx: Int = DEFAULT_QR_SIZE_PX): ByteArray? {
        val clean = payload.trim()
        if (clean.isEmpty()) return null
        val hints = mapOf(
            EncodeHintType.CHARACTER_SET to "UTF-8",
            EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to ISO_QUIET_ZONE_MODULES
        )
        val matrix = QRCodeWriter().encode(clean, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
        val w = matrix.width
        val h = matrix.height
        val pixels = IntArray(w * h)
        for (y in 0 until h) {
            val rowOffset = y * w
            for (x in 0 until w) {
                pixels[rowOffset + x] = if (matrix[x, y]) Color.BLACK else Color.WHITE
            }
        }
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.setPixels(pixels, 0, w, 0, 0, w, h)
        return try {
            ByteArrayOutputStream().use { baos ->
                if (!bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)) return null
                baos.toByteArray()
            }
        } finally {
            if (!bmp.isRecycled) bmp.recycle()
        }
    }

    /**
     * Saves the generated 1024x1024 QR PNG to Pictures/PresenterSync on Android 10+ (API 29+)
     * with zero storage runtime permissions, or returns [SaveResult.RequiresDocumentPicker] on API 26-28.
     */
    fun saveQrToGallery(context: Context, payload: String): SaveResult {
        val pngBytes = encodeQrPngBytes(payload)
            ?: return SaveResult.Failed("Unable to encode pairing QR image")
        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val fileName = "PresenterSync_QR_$stamp.png"

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return SaveResult.RequiresDocumentPicker(fileName, pngBytes)
        }

        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/PresenterSync")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        val itemUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return SaveResult.Failed("MediaStore insert failed")

        return try {
            resolver.openOutputStream(itemUri)?.use { out ->
                out.write(pngBytes)
                out.flush()
            } ?: throw IllegalStateException("Could not open MediaStore output stream")

            val publishValues = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(itemUri, publishValues, null, null)
            SaveResult.SavedToGallery("Pictures/PresenterSync/$fileName", itemUri)
        } catch (t: Throwable) {
            runCatching { resolver.delete(itemUri, null, null) }
            SaveResult.Failed(t.message ?: "Failed saving QR image")
        }
    }
}
