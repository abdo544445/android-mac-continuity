package com.continuity.ecosystem.files

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.connection.RawBinaryChunk
import com.continuity.ecosystem.core.*
import kotlinx.coroutines.*
import java.io.File
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
            val fileBytes = context.contentResolver.openInputStream(fileUri)?.use { it.readBytes() } ?: return@launch
            val fileSize = fileBytes.size.toLong()
            val checksum = identity.sha256Hex(fileBytes)
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

            val totalChunks = ((fileBytes.size + effectiveChunkSize - 1) / effectiveChunkSize)
            val offer = TransferOffer(
                transferId = transferId,
                fileName = fileName,
                fileSizeBytes = fileSize,
                sha256Checksum = checksum,
                totalChunks = totalChunks,
                chunkSizeBytes = effectiveChunkSize.toLong()
            )

            service.sendEnvelope(ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                transferOffer = offer
            ))

            var offset = 0
            var chunkIndex = 0

            while (offset < fileBytes.size) {
                val len = minOf(effectiveChunkSize, fileBytes.size - offset)
                val chunk = fileBytes.copyOfRange(offset, offset + len)

                val rawChunk = RawBinaryChunk(
                    transferId = transferId,
                    chunkIndex = chunkIndex,
                    chunkTotal = totalChunks,
                    data = chunk
                )
                service.sendBinaryChunk(rawChunk)

                offset += len
                chunkIndex++
                item.bytesTransferred = offset.toLong()
                withContext(Dispatchers.Main) { onTransfersUpdated?.invoke() }
            }

            service.sendEnvelope(ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                transferComplete = TransferComplete(
                    transferId = transferId,
                    verified = true,
                    finalPathBasename = fileName,
                    bytesWritten = fileSize
                )
            ))

            item.isCompleted = true
            withContext(Dispatchers.Main) { onTransfersUpdated?.invoke() }
        }
    }

    fun handleIncomingOffer(offer: TransferOffer, service: ConnectionService) {
        val item = AndroidTransferItem(
            id = offer.transferId,
            fileName = offer.fileName,
            totalBytes = offer.fileSizeBytes,
            isIncoming = true
        )
        synchronized(activeTransfers) {
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
        scope.launch(Dispatchers.Main) { onTransfersUpdated?.invoke() }
    }

    fun handleIncomingChunk(chunk: TransferChunk) {
        // Fallback for JSON Base64 chunks if received
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
        scope.launch(Dispatchers.Main) { onTransfersUpdated?.invoke() }
    }

    fun handleIncomingComplete(complete: TransferComplete) {
        val rawName = File(complete.finalPathBasename).name
        val fileName = if (rawName.isEmpty()) "file.bin" else rawName
        val dir = File(context.filesDir, "transfers").also { it.mkdirs() }
        val tempFile = File(dir, "${complete.transferId}.part")

        var destination = File(dir, fileName)
        var counter = 1
        val baseName = destination.nameWithoutExtension
        val ext = destination.extension

        while (destination.exists()) {
            val newName = if (ext.isEmpty()) "$baseName ($counter)" else "$baseName ($counter).$ext"
            destination = File(dir, newName)
            counter++
        }

        tempFile.renameTo(destination)

        synchronized(activeTransfers) {
            val item = activeTransfers.find { it.id == complete.transferId }
            item?.let {
                it.isCompleted = true
                it.bytesTransferred = complete.bytesWritten
            }
        }
        scope.launch(Dispatchers.Main) { onTransfersUpdated?.invoke() }
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
