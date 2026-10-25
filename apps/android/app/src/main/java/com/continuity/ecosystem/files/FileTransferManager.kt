package com.continuity.ecosystem.files

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Log
import android.widget.Toast
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.connection.RawBinaryChunk
import com.continuity.ecosystem.core.*
import kotlinx.coroutines.*
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID

data class AndroidTransferItem(
    val id: String,
    val fileName: String,
    val totalBytes: Long,
    var bytesTransferred: Long = 0,
    val isIncoming: Boolean,
    var isCompleted: Boolean = false,
    var isFailed: Boolean = false
) {
    val progress: Float
        get() = if (totalBytes > 0) bytesTransferred.toFloat() / totalBytes else 0f
}

class FileTransferManager(
    private val context: Context,
    private val identity: DeviceIdentity
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val activeTransfers = mutableListOf<AndroidTransferItem>()
    var onTransfersUpdated: (() -> Unit)? = null
    private var lastUiUpdateMs: Long = 0L

    companion object {
        fun adaptiveChunkSize(fileSizeBytes: Long): Int {
            return when {
                fileSizeBytes < 5 * 1024 * 1024 -> 256 * 1024 // 256 KB
                fileSizeBytes < 50 * 1024 * 1024 -> 1024 * 1024 // 1 MB
                else -> 4 * 1024 * 1024 // 4 MB for large/USB transfers
            }
        }
    }

    fun sendFile(fileUri: Uri, service: ConnectionService) {
        scope.launch {
            val fileName = getFileName(fileUri) ?: "file.bin"
            val fileSize = getFileSize(fileUri)
            val transferId = UUID.randomUUID().toString()
            val effectiveChunkSize = adaptiveChunkSize(fileSize)

            val item = AndroidTransferItem(
                id = transferId,
                fileName = fileName,
                totalBytes = fileSize,
                isIncoming = false
            )
            synchronized(activeTransfers) {
                activeTransfers.add(0, item)
            }
            withContext(Dispatchers.Main) { onTransfersUpdated?.invoke() }

            val totalChunks = if (fileSize > 0) ((fileSize + effectiveChunkSize - 1) / effectiveChunkSize).toInt() else 1
            val offer = TransferOffer(
                transferId = transferId,
                fileName = fileName,
                fileSizeBytes = fileSize,
                sha256Checksum = "streamed-binary",
                totalChunks = totalChunks,
                chunkSizeBytes = effectiveChunkSize.toLong()
            )

            service.sendEnvelope(ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                transferOffer = offer
            ))

            var offset = 0L
            var chunkIndex = 0
            val buffer = ByteArray(effectiveChunkSize)

            context.contentResolver.openInputStream(fileUri)?.use { input ->
                while (true) {
                    var bytesReadTotal = 0
                    while (bytesReadTotal < effectiveChunkSize) {
                        val r = input.read(buffer, bytesReadTotal, effectiveChunkSize - bytesReadTotal)
                        if (r == -1) break
                        bytesReadTotal += r
                    }
                    if (bytesReadTotal <= 0) break

                    val chunk = if (bytesReadTotal == effectiveChunkSize) buffer.clone() else buffer.copyOfRange(0, bytesReadTotal)
                    val rawChunk = RawBinaryChunk(
                        transferId = transferId,
                        chunkIndex = chunkIndex,
                        chunkTotal = totalChunks,
                        data = chunk
                    )
                    service.sendBinaryChunkSync(rawChunk)

                    offset += bytesReadTotal
                    chunkIndex++
                    item.bytesTransferred = offset
                    notifyProgressThrottled()
                }
            }

            service.sendEnvelope(ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                transferComplete = TransferComplete(
                    transferId = transferId,
                    verified = true,
                    finalPathBasename = fileName,
                    bytesWritten = offset
                )
            ))

            item.isCompleted = true
            item.bytesTransferred = offset
            withContext(Dispatchers.Main) { onTransfersUpdated?.invoke() }
        }
    }

    fun handleIncomingOffer(offer: TransferOffer, service: ConnectionService) {
        Log.w("ContinuityDebug", "Incoming file offer: ${offer.fileName} (${offer.fileSizeBytes} bytes)")
        val item = AndroidTransferItem(
            id = offer.transferId,
            fileName = offer.fileName,
            totalBytes = offer.fileSizeBytes,
            isIncoming = true
        )
        synchronized(activeTransfers) {
            activeTransfers.removeAll { it.id == offer.transferId }
            activeTransfers.add(0, item)
        }
        onTransfersUpdated?.invoke()

        // Auto-accept offer
        service.sendEnvelope(ContinuityEnvelope(
            senderDeviceId = identity.deviceId,
            transferAccept = TransferAccept(transferId = offer.transferId)
        ))
    }

    fun handleIncomingBinaryChunk(chunk: RawBinaryChunk) {
        val dir = File(context.filesDir, "transfers").also { it.mkdirs() }
        val tempFile = File(dir, "${chunk.transferId}.part")
        FileOutputStream(tempFile, true).use { it.write(chunk.data) }

        synchronized(activeTransfers) {
            val item = activeTransfers.find { it.id == chunk.transferId }
            item?.let {
                it.bytesTransferred += chunk.data.size
            }
        }
        notifyProgressThrottled()
    }

    fun handleIncomingChunk(chunk: TransferChunk) {
        val chunkBytes = Base64.decode(chunk.dataBase64, Base64.NO_WRAP)
        val computedHash = identity.sha256Hex(chunkBytes)
        if (computedHash != chunk.chunkSha256) return

        val dir = File(context.filesDir, "transfers").also { it.mkdirs() }
        val tempFile = File(dir, "${chunk.transferId}.part")
        FileOutputStream(tempFile, true).use { it.write(chunkBytes) }

        synchronized(activeTransfers) {
            val item = activeTransfers.find { it.id == chunk.transferId }
            item?.let {
                it.bytesTransferred += chunkBytes.size
            }
        }
        notifyProgressThrottled()
    }

    fun handleIncomingComplete(complete: TransferComplete) {
        scope.launch(Dispatchers.IO) {
            val rawName = File(complete.finalPathBasename).name
            val fileName = if (rawName.isEmpty()) "file.bin" else rawName
            val dir = File(context.filesDir, "transfers").also { it.mkdirs() }
            val tempFile = File(dir, "${complete.transferId}.part")

            var savedToDownloads = false
            if (tempFile.exists()) {
                savedToDownloads = exportToPublicDownloads(tempFile, fileName)
                if (savedToDownloads) {
                    tempFile.delete()
                } else {
                    val destination = File(dir, fileName)
                    tempFile.renameTo(destination)
                }
            }

            synchronized(activeTransfers) {
                val item = activeTransfers.find { it.id == complete.transferId }
                item?.let {
                    it.isCompleted = true
                    it.bytesTransferred = complete.bytesWritten
                }
            }
            Log.w("ContinuityDebug", "Transfer complete: $fileName (exportedToDownloads=$savedToDownloads)")
            withContext(Dispatchers.Main) {
                onTransfersUpdated?.invoke()
                Toast.makeText(
                    context,
                    "Saved to Downloads/Continuity: $fileName",
                    Toast.LENGTH_LONG
                ).show()
            }
        }
    }

    private fun exportToPublicDownloads(sourceFile: File, fileName: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Continuity")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = context.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
                resolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(sourceFile).use { input ->
                        input.copyTo(out, bufferSize = 1024 * 1024)
                    }
                }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                true
            } else {
                val pubDir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "Continuity"
                ).also { it.mkdirs() }
                val dest = File(pubDir, fileName)
                sourceFile.copyTo(dest, overwrite = true)
                true
            }
        } catch (e: Exception) {
            Log.e("ContinuityDebug", "Failed to export to public Downloads: ${e.message}", e)
            false
        }
    }

    private fun notifyProgressThrottled() {
        val now = System.currentTimeMillis()
        if (now - lastUiUpdateMs >= 150L) {
            lastUiUpdateMs = now
            scope.launch(Dispatchers.Main) { onTransfersUpdated?.invoke() }
        }
    }

    private fun getFileSize(uri: Uri): Long {
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (idx != -1 && !cursor.isNull(idx)) return cursor.getLong(idx)
                }
            }
        }
        return context.contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize } ?: 0L
    }

    private fun getFileName(uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx != -1) name = cursor.getString(idx)
                }
            }
        }
        if (name == null) {
            name = uri.path
            val cut = name?.lastIndexOf('/') ?: -1
            if (cut != -1) name = name?.substring(cut + 1)
        }
        return name
    }
}
