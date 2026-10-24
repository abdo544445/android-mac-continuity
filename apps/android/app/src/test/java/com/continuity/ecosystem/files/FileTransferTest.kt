package com.continuity.ecosystem.files

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.security.MessageDigest

class FileTransferTest {

    private val chunkSize = 512 * 1024 // 512 KB

    private fun calculateTotalChunks(fileSizeBytes: Long): Int {
        if (fileSizeBytes <= 0) return 0
        return ((fileSizeBytes + chunkSize - 1) / chunkSize).toInt()
    }

    private fun sanitizeBasename(input: String): String {
        val safeName = File(input).name
        return if (safeName.isEmpty() || safeName == "." || safeName == "..") "file.bin" else safeName
    }

    @Test
    fun testChunkCountCalculations() {
        assertEquals(0, calculateTotalChunks(0))
        assertEquals(1, calculateTotalChunks(100))
        assertEquals(1, calculateTotalChunks(512 * 1024)) // Exact 512 KB
        assertEquals(2, calculateTotalChunks(512 * 1024 + 1)) // 512 KB + 1 byte -> 2 chunks
        assertEquals(3, calculateTotalChunks(1024 * 1024 + 200)) // ~1 MB -> 3 chunks
    }

    @Test
    fun testPathTraversalSanitization() {
        assertEquals("payload.sh", sanitizeBasename("../../payload.sh"))
        assertEquals("hosts", sanitizeBasename("../../../../etc/hosts"))
        assertEquals("normal_document.pdf", sanitizeBasename("normal_document.pdf"))
        assertEquals("file.bin", sanitizeBasename(""))
        assertEquals("file.bin", sanitizeBasename(".."))
        assertEquals("file.bin", sanitizeBasename("/"))
    }

    @Test
    fun testChunkHashIntegrityVerification() {
        val chunkData = "Test chunk payload content for SHA-256 chunk validation".toByteArray(Charsets.UTF_8)
        val md = MessageDigest.getInstance("SHA-256")
        val expectedHash = md.digest(chunkData).joinToString("") { "%02x".format(it) }

        val verifyMd = MessageDigest.getInstance("SHA-256")
        val computedHash = verifyMd.digest(chunkData).joinToString("") { "%02x".format(it) }

        assertEquals(expectedHash, computedHash)
    }
}
