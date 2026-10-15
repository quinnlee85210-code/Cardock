package com.localaccount.account_subscription_manager

internal data class OwnershipDecision(val licensed: Boolean, val clearCache: Boolean)
internal object BillingOwnershipPolicy {
    fun afterQuery(previousVerified: Boolean, querySucceeded: Boolean,
        hasMatchingProduct: Boolean, verifiedAndAcknowledged: Boolean): OwnershipDecision = when {
        !querySucceeded -> OwnershipDecision(previousVerified, false)
        verifiedAndAcknowledged -> OwnershipDecision(true, false)
        !hasMatchingProduct -> OwnershipDecision(false, true)
        // Pending, malformed, or acknowledgement failure cannot grant; neither proves revocation.
        else -> OwnershipDecision(previousVerified, false)
    }
}
