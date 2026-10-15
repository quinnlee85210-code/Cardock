package com.localaccount.account_subscription_manager

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

/** Metadata is a preflight hint; always enforce the limit on the stream itself. */
internal object BoundedDocumentReader {
    const val BACKUP_LIMIT = 16 * 1024 * 1024
    const val IMPORT_LIMIT = 10 * 1024 * 1024
    fun read(limit: Int, declaredSize: Long?, open: () -> InputStream): ByteArray {
        require(limit in 1..BACKUP_LIMIT)
        if (declaredSize != null && declaredSize > limit) throw IOException("document_too_large")
        val output = object : ByteArrayOutputStream() {
            fun erase() { buf.fill(0); reset() }
        }
        val buffer = ByteArray(65536)
        try {
            open().use { input ->
                while (true) {
                    // At most one excess byte is read, even if the provider lies about length.
                    val count = input.read(buffer, 0, minOf(buffer.size, limit - output.size() + 1))
                    if (count < 0) break
                    if (count == 0) throw IOException("document_read_stalled")
                    if (count > limit - output.size()) throw IOException("document_too_large")
                    output.write(buffer, 0, count)
                }
            }
            if (output.size() == 0) throw IOException("document_empty")
            return output.toByteArray()
        } finally { buffer.fill(0); output.erase() }
    }
}
