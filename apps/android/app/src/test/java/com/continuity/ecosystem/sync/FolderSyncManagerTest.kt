package com.continuity.ecosystem.sync

import com.continuity.ecosystem.core.FolderSyncManifest
import com.continuity.ecosystem.core.SyncFileEntry
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest

class FolderSyncManagerTest {

    @Test
    fun testSyncFileEntryCreationAndIntegrity() {
        val testContent = "Sync file content test string"
        val md = MessageDigest.getInstance("SHA-256")
        val expectedHash = md.digest(testContent.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

        val entry = SyncFileEntry(
            path = "docs/report.txt",
            sizeBytes = testContent.length.toLong(),
            sha256 = expectedHash,
            modifiedTimeMs = 1729000000000L
        )

        assertEquals("docs/report.txt", entry.path)
        assertEquals(testContent.length.toLong(), entry.sizeBytes)
        assertEquals(expectedHash, entry.sha256)
        assertEquals(1729000000000L, entry.modifiedTimeMs)
    }

    @Test
    fun testFolderSyncManifestDeduplication() {
        val file1 = SyncFileEntry("a.txt", 100L, "hash_a", 1000L)
        val file2 = SyncFileEntry("b.png", 200L, "hash_b", 2000L)

        val manifest = FolderSyncManifest(
            syncId = "sync-test-99",
            folderName = "ContinuitySync",
            files = listOf(file1, file2)
        )

        assertEquals("ContinuitySync", manifest.folderName)
        assertEquals(2, manifest.files.size)

        // Remote peer manifest comparison logic
        val remoteManifest = FolderSyncManifest(
            syncId = "remote-99",
            folderName = "ContinuitySync",
            files = listOf(
                SyncFileEntry("a.txt", 100L, "hash_a", 1000L), // identical -> skip
                SyncFileEntry("c.pdf", 300L, "hash_c", 3000L)  // missing locally -> needs sync
            )
        )

        val localHashMap = manifest.files.associateBy { it.path }
        val missingOrModified = remoteManifest.files.filter { remote ->
            val local = localHashMap[remote.path]
            local == null || local.sha256 != remote.sha256
        }

        assertEquals(1, missingOrModified.size)
        assertEquals("c.pdf", missingOrModified[0].path)
    }
}
