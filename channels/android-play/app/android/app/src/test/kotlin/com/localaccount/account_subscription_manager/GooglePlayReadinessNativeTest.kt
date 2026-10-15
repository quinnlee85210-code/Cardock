package com.localaccount.account_subscription_manager

import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream

internal object GooglePlayReadinessNativeTest {
    @JvmStatic fun main(args: Array<String>) {
        var cases = 0
        class Tracked(private val size: Int, private val broken: Boolean = false) : InputStream() {
            var consumed = 0; var closed = false
            override fun read(): Int { if (broken) throw IOException(); return if (consumed++ < size) 42 else -1 }
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (broken) throw IOException()
                val n = minOf(len, size - consumed); if (n <= 0) return -1
                b.fill(42, off, off+n); consumed += n; return n
            }
            override fun close() { closed = true }
        }
        fun reject(block: () -> Unit) { check(runCatching(block).exceptionOrNull() is IOException); cases++ }
        for (declared in listOf<Long?>(null, -1, 0, 8, 32)) {
            val input = Tracked(32)
            check(BoundedDocumentReader.read(32, declared) { input }.size == 32)
            check(input.closed); cases++
        }
        var opened = false
        reject { BoundedDocumentReader.read(32, 33) { opened = true; ByteArrayInputStream(byteArrayOf(1)) } }
        check(!opened)
        for (declared in listOf<Long?>(null, 0, 1, 32)) {
            val input = Tracked(1000000)
            reject { BoundedDocumentReader.read(32, declared) { input } }
            check(input.closed && input.consumed == 33)
        }
        for (input in listOf(Tracked(0), Tracked(2, true))) {
            reject { BoundedDocumentReader.read(32, null) { input } }; check(input.closed)
        }
        val boundary = Tracked(BoundedDocumentReader.BACKUP_LIMIT)
        check(BoundedDocumentReader.read(BoundedDocumentReader.BACKUP_LIMIT, null) { boundary }.size == BoundedDocumentReader.BACKUP_LIMIT)
        check(boundary.closed); cases++
        for (prior in listOf(false,true)) {
            check(BillingOwnershipPolicy.afterQuery(prior,false,false,false) == OwnershipDecision(prior,false)); cases++
            check(BillingOwnershipPolicy.afterQuery(prior,true,true,false) == OwnershipDecision(prior,false)); cases++
            check(BillingOwnershipPolicy.afterQuery(prior,true,false,false) == OwnershipDecision(false,true)); cases++
            check(BillingOwnershipPolicy.afterQuery(prior,true,true,true) == OwnershipDecision(true,false)); cases++
        }
        println("GooglePlayReadinessNativeTest: $cases cases passed")
    }
}
