package com.localaccount.account_subscription_manager

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

internal object PlayBillingReceiptVerifier {
    fun configured(publicKey: String): Boolean = try {
        val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(publicKey))) as java.security.interfaces.RSAPublicKey
        key.modulus.bitLength() >= 2048
    } catch (_: Exception) { false }
    fun verify(publicKey: String, data: String, signature: String): Boolean = try {
        if (publicKey.isBlank() || data.isBlank() || data.length > 16384 || signature.length > 2048) false
        else {
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(publicKey)))
            // Google Play's client purchase-data signature uses this protocol algorithm.
            Signature.getInstance("SHA1withRSA").run {
                initVerify(key); update(data.toByteArray(Charsets.UTF_8)); verify(Base64.getDecoder().decode(signature))
            }
        }
    } catch (_: Exception) { false }
}
