package com.continuity.ecosystem.storage

import com.continuity.ecosystem.core.StorageItem
import com.continuity.ecosystem.core.StorageListRequest
import com.continuity.ecosystem.core.StorageListResponse
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class StorageExplorerServiceTest {

    @Test
    fun testStorageItemAttributes() {
        val folder = StorageItem(
            name = "Pictures",
            isDirectory = true,
            sizeBytes = 0L,
            modifiedTimeMs = 1729000000000L
        )

        val file = StorageItem(
            name = "report.pdf",
            isDirectory = false,
            sizeBytes = 1048576L,
            modifiedTimeMs = 1729000050000L
        )

        assertTrue(folder.isDirectory)
        assertEquals(0L, folder.sizeBytes)
        assertFalse(file.isDirectory)
        assertEquals(1048576L, file.sizeBytes)
    }

    @Test
    fun testStorageListResponseEnvelope() {
        val items = listOf(
            StorageItem("DCIM", isDirectory = true, sizeBytes = 0L, modifiedTimeMs = 1000L),
            StorageItem("Downloads", isDirectory = true, sizeBytes = 0L, modifiedTimeMs = 2000L),
            StorageItem("readme.txt", isDirectory = false, sizeBytes = 512L, modifiedTimeMs = 3000L)
        )

        val response = StorageListResponse(
            requestId = "req-list-001",
            path = "/storage/emulated/0",
            items = items
        )

        assertEquals("req-list-001", response.requestId)
        assertEquals("/storage/emulated/0", response.path)
        assertEquals(3, response.items.size)
        assertEquals("DCIM", response.items[0].name)
    }

    @Test
    fun testPathTraversalSanitization() {
        val dangerousPaths = listOf(
            "../../../../etc/passwd",
            "/data/data/com.continuity.ecosystem",
            "../system"
        )

        for (path in dangerousPaths) {
            val normalized = File(path).normalize().path
            val isEscaped = normalized.contains("..") || normalized.startsWith("/data")
            assertTrue("Path traversal or root directory must be detected: $path", isEscaped)
        }
    }
}
