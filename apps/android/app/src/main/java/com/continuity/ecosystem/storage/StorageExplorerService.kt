package com.continuity.ecosystem.storage

import android.content.Context
import android.os.Environment
import android.util.Log
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.StorageItem
import com.continuity.ecosystem.core.StorageListRequest
import com.continuity.ecosystem.core.StorageListResponse
import java.io.File

class StorageExplorerService(private val context: Context) {

    fun handleStorageListRequest(request: StorageListRequest, service: ConnectionService) {
        val targetPath = if (request.path.isEmpty() || request.path == "/" || request.path == "~") {
            Environment.getExternalStorageDirectory()?.absolutePath ?: context.filesDir.absolutePath
        } else {
            request.path
        }

        Log.d("ContinuityDebug", "StorageExplorer: Listing directory: $targetPath")
        val dir = File(targetPath)
        val items = mutableListOf<StorageItem>()

        if (dir.exists() && dir.isDirectory) {
            val fileList = dir.listFiles()
            if (fileList != null) {
                for (f in fileList) {
                    // Filter out hidden/system internal cache dotfiles if desired
                    if (f.name.startsWith(".") && f.name != ".ContinuitySync") continue
                    items.add(
                        StorageItem(
                            name = f.name,
                            isDirectory = f.isDirectory,
                            sizeBytes = if (f.isDirectory) 0L else f.length(),
                            modifiedTimeMs = f.lastModified()
                        )
                    )
                }
            }
        } else {
            Log.w("ContinuityDebug", "StorageExplorer: Path $targetPath is not a directory or inaccessible")
        }

        // Sort: directories first, then alphabetical
        items.sortWith(compareBy({ !it.isDirectory }, { it.name.lowercase() }))

        val response = StorageListResponse(
            requestId = request.requestId,
            path = targetPath,
            items = items
        )

        service.sendEnvelope(
            ContinuityEnvelope(
                senderDeviceId = "android",
                storageListResponse = response
            )
        )
    }
}
