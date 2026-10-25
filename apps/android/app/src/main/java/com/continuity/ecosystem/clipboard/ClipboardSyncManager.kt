package com.continuity.ecosystem.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ClipboardPayload
import com.continuity.ecosystem.core.ContinuityEnvelope
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class ClipboardSyncManager(private val context: Context) {
    private val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    fun sendCurrentClipboard(service: ConnectionService) {
        val primaryClip = clipboard.primaryClip
        if (primaryClip != null && primaryClip.itemCount > 0) {
            val item = primaryClip.getItemAt(0)

            // 1. Check if clipboard item has an image URI
            val uri = item.uri
            if (uri != null) {
                val mime = context.contentResolver.getType(uri) ?: ""
                if (mime.startsWith("image/")) {
                    try {
                        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                            val bmp = BitmapFactory.decodeStream(input)
                            val out = ByteArrayOutputStream()
                            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                            out.toByteArray()
                        }
                        if (bytes != null && bytes.isNotEmpty()) {
                            val payload = ClipboardPayload(
                                clipId = UUID.randomUUID().toString(),
                                dataBase64 = Base64.encodeToString(bytes, Base64.NO_WRAP),
                                mimeType = "image/png"
                            )
                            service.sendEnvelope(
                                ContinuityEnvelope(
                                    senderDeviceId = "android",
                                    clipboardPayload = payload
                                )
                            )
                            Toast.makeText(context, "Image clipboard sent to Mac", Toast.LENGTH_SHORT).show()
                            return
                        }
                    } catch (e: Exception) {
                        Log.e("ContinuityDebug", "Failed to read image from Android clipboard: ${e.message}")
                    }
                }
            }

            // 2. Otherwise send plain text
            val text = item.coerceToText(context)?.toString()
            if (!text.isNullOrEmpty()) {
                val payload = ClipboardPayload(
                    clipId = UUID.randomUUID().toString(),
                    dataBase64 = Base64.encodeToString(text.toByteArray(Charsets.UTF_8), Base64.NO_WRAP),
                    mimeType = "text/plain"
                )
                service.sendEnvelope(
                    ContinuityEnvelope(
                        senderDeviceId = "android",
                        clipboardPayload = payload
                    )
                )
                Toast.makeText(context, "Clipboard sent to Mac", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun handleIncomingClipboard(payload: ClipboardPayload) {
        try {
            val bytes = Base64.decode(payload.dataBase64, Base64.NO_WRAP)

            // Handle Image Clipboard from Mac (PNG / TIFF converted to PNG)
            if (payload.mimeType.startsWith("image/")) {
                val imageUri = saveImageToMediaStoreForClipboard(bytes, payload.clipId)
                if (imageUri != null) {
                    val clip = ClipData.newUri(context.contentResolver, "Mac Image", imageUri)
                    clipboard.setPrimaryClip(clip)
                    Log.w("ContinuityDebug", "Image copied from Mac to Android Clipboard URI: $imageUri")
                    Toast.makeText(
                        context,
                        "🖼️ Image copied from Mac — ready to paste!",
                        Toast.LENGTH_SHORT
                    ).show()
                }
                return
            }

            // Handle Text Clipboard from Mac
            val text = String(bytes, Charsets.UTF_8)
            val clip = ClipData.newPlainText("Continuity", text)
            clipboard.setPrimaryClip(clip)
            Log.w("ContinuityDebug", "Text copied from Mac to Android Clipboard (${text.length} chars)")
            Toast.makeText(context, "📋 Copied from Mac: ${text.take(30)}", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "handleIncomingClipboard error: ${e.message}", e)
        }
    }

    /**
     * Inserts the received PNG image into Android's MediaStore.Images so that any app on Huawei/Android
     * (Notes, Telegram, Docs, Browser, etc.) has read permission to paste the image URI directly.
     */
    private fun saveImageToMediaStoreForClipboard(pngBytes: ByteArray, clipId: String): Uri? {
        return try {
            val fileName = "MacClip_${clipId.take(8)}.png"
            val resolver = context.contentResolver

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Continuity")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return null
                resolver.openOutputStream(uri)?.use { out ->
                    out.write(pngBytes)
                }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                uri
            } else {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "Continuity"
                ).also { it.mkdirs() }
                val file = File(dir, fileName)
                FileOutputStream(file).use { it.write(pngBytes) }
                Uri.fromFile(file)
            }
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "saveImageToMediaStoreForClipboard failed: ${e.message}", e)
            null
        }
    }
}
