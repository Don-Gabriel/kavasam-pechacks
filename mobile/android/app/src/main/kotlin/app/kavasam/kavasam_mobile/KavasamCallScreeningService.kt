package app.kavasam.kavasam_mobile

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telecom.Connection

class KavasamCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        val number = callDetails.handle?.schemeSpecificPart ?: "Unknown number"
        val incoming = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            callDetails.callDirection == Call.Details.DIRECTION_INCOMING
        } else {
            true
        }
        val verificationFailed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            callDetails.callerNumberVerificationStatus == Connection.VERIFICATION_STATUS_FAILED
        } else {
            false
        }
        val identity = CallerIdentityStore.assess(
            context = applicationContext,
            rawNumber = number,
            direction = if (incoming) "incoming" else "outgoing",
            verificationFailed = verificationFailed,
            recordScreening = incoming,
        )

        if (!incoming) return

        val shouldBlock = CallProtectionSettings.shouldBlock(applicationContext, identity)
        val response = CallResponse.Builder()
            .setDisallowCall(shouldBlock)
            .setRejectCall(shouldBlock)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
        respondToCall(callDetails, response)
    }
}
