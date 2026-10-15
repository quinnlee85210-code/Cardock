package com.localaccount.account_subscription_manager
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
object PlayBillingReceiptNativeTest {
 @JvmStatic fun main(args: Array<String>) {
  val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
  val publicKey = Base64.getEncoder().encodeToString(pair.public.encoded)
  val data = "test-only-purchase-data"
  val signature = Signature.getInstance("SHA1withRSA").run { initSign(pair.private); update(data.toByteArray()); Base64.getEncoder().encodeToString(sign()) }
  check(PlayBillingReceiptVerifier.configured(publicKey))
  check(!PlayBillingReceiptVerifier.configured("malformed"))
  check(PlayBillingReceiptVerifier.verify(publicKey,data,signature))
  check(!PlayBillingReceiptVerifier.verify(publicKey,data+"tampered",signature))
  check(!PlayBillingReceiptVerifier.verify(publicKey,data,"bad"))
  check(!PlayBillingReceiptVerifier.verify("",data,signature))
  check(!PlayBillingReceiptVerifier.verify(publicKey,"x".repeat(16385),signature))
  val other = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
  check(!PlayBillingReceiptVerifier.verify(Base64.getEncoder().encodeToString(other.public.encoded),data,signature))
  println("PlayBillingReceiptNativeTest: 8 cryptographic checks passed")
 }
}
