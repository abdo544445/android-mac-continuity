package com.continuity.ecosystem.files

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import com.continuity.ecosystem.connection.ConnectionService
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

    private val chunkSize = 512 * 1024 // 512 KB

    fun sendFile(fileUri: Uri, service: ConnectionService) {
        scope.launch {
            val fileName = getFileName(fileUri) ?: "file.bin"
            val fileBytes = context.contentResolver.openInputStream(fileUri)?.use { it.readBytes() } ?: return@launch
            val fileSize = fileBytes.size.toLong()
            val checksum = identity.sha256Hex(fileBytes)
            val transferId = UUID.randomUUID().toString()

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

            val totalChunks = ((fileBytes.size + chunkSize - 1) / chunkSize)
            val offer = TransferOffer(
                transferId = transferId,
                fileName = fileName,
                fileSizeBytes = fileSize,
                sha256Checksum = checksum,
                totalChunks = totalChunks,
                chunkSizeBytes = chunkSize.toLong()
            )

            service.sendEnvelope(ContinuityEnvelope(
                senderDeviceId = identity.deviceId,
                transferOffer = offer
            ))

            var offset = 0
            var chunkIndex = 0

            while (offset < fileBytes.size) {
                val len = minOf(chunkSize, fileBytes.size - offset)
                val chunk = fileBytes.copyOfRange(offset, offset + len)
                val chunkHash = identity.sha256Hex(chunk)

                val chunkMsg = TransferChunk(
                    transferId = transferId,
                    chunkIndex = chunkIndex,
                    dataBase64 = Base64.encodeToString(chunk, Base64.NO_WRAP),
                    chunkSha256 = chunkHash
                )

                service.sendEnvelope(ContinuityEnvelope(
                    senderDeviceId = identity.deviceId,
                    transferChunk = chunkMsg
                ))

                offset += len
                chunkIndex++
                item.bytesTransferred = offset.toLong()
                withContext(Dispatchers.Main) { onTransfersUpdated?.invoke() }
                delay(2) // 2ms rate limit
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

    fun handleIncomingChunk(chunk: TransferChunk) {
        val chunkBytes = Base64.decode(chunk.dataBase64, Base64.NO_WRAP)
        val computedHash = identity.sha256Hex(chunkBytes)
        if (computedHash != chunk.chunkSha256) return

        val dir = File(context.filesDir, "transfers").also { it.mkdirs() }
        val tempFile = File(dir, "${chunk.transferId}.part")
        FileOutputStream(tempFile, true).use { it.write(chunkBytes) }

        synchronized(activeTransfers) {
            activeTransfers.find { it.id == chunk.transferId }?.let {
                it.bytesTransferred += chunkBytes.size
            }
        }
        onTransfersUpdated?.invoke()
    }

    fun handleIncomingComplete(complete: TransferComplete) {
        val dir = File(context.filesDir, "transfers")
        val tempFile = File(dir, "${complete.transferId}.part")
        val destFile = File(dir, complete.finalPathBasename)
        tempFile.renameTo(destFile)

        synchronized(activeTransfers) {
            activeTransfers.find { it.id == complete.transferId }?.let {
                it.isCompleted = true
            }
        }
        onTransfersUpdated?.invoke()
    }

    private fun getFileName(uri: Uri): String? {
        var name: String? = null
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && nameIndex >= 0) {
                name = cursor.getString(nameIndex)
            }
        }
        return name ?: uri.lastPathSegment
    }
}
