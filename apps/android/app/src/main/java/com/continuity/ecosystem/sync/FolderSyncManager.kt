package com.continuity.ecosystem.sync

import android.content.Context
import android.os.Environment
import android.util.Log
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.FolderSyncManifest
import com.continuity.ecosystem.core.SyncFileEntry
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

class FolderSyncManager(private val context: Context) {

    private val syncFolder: File by lazy {
        val docs = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val dir = File(docs, "ContinuitySync")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        dir
    }

    fun generateManifest(): FolderSyncManifest {
        val entries = mutableListOf<SyncFileEntry>()
        val files = syncFolder.listFiles()
        if (files != null) {
            for (f in files) {
                if (f.isFile && !f.name.startsWith(".")) {
                    val hash = calculateSha256(f)
                    entries.add(
                        SyncFileEntry(
                            path = f.name,
                            sizeBytes = f.length(),
                            sha256 = hash,
                            modifiedTimeMs = f.lastModified()
                        )
                    )
                }
            }
        }
        return FolderSyncManifest(folderName = "ContinuitySync", files = entries)
    }

    fun handleIncomingManifest(manifest: FolderSyncManifest, service: ConnectionService) {
        Log.d("ContinuityDebug", "FolderSync: Received manifest with ${manifest.files.size} files")
        val localManifest = generateManifest()

        // Reply with our own manifest so both devices reconcile
        val reply = ContinuityEnvelope(
            senderDeviceId = "android",
            folderSyncManifest = localManifest
        )
        service.sendEnvelope(reply)
    }

    private fun calculateSha256(file: File): String {
        return try {
            val md = MessageDigest.getInstance("SHA-256")
            FileInputStream(file).use { fis ->
                val buffer = ByteArray(8192)
                var read: Int
                while (fis.read(buffer).also { read = it } != -1) {
                    md.update(buffer, 0, read)
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            ""
        }
    }
}
