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
        } else true
        val verification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            when (callDetails.callerNumberVerificationStatus) {
                Connection.VERIFICATION_STATUS_FAILED -> "failed"
                Connection.VERIFICATION_STATUS_PASSED -> "passed"
                else -> "not_verified"
            }
        } else "not_available"
        ProtectionStore.preferences(this).edit()
            .putString(ProtectionStore.CALL_NUMBER, number)
            .putString(ProtectionStore.CALL_VERIFICATION, verification)
            .putString(ProtectionStore.CALL_DIRECTION, if (incoming) "incoming" else "outgoing")
            .putLong(ProtectionStore.CALL_TIMESTAMP, System.currentTimeMillis())
            .apply()
        if (incoming) {
            val message = if (verification == "failed") {
                "The network could not verify $number. Be careful with money or identity requests."
            } else {
                "$number was screened. Use Protect Call if the caller asks for money or secrets."
            }
            KavasamAlerts.show(this, "Incoming call screened", message, 3102)
            respondToCall(
                callDetails,
                CallResponse.Builder()
                    .setDisallowCall(false)
                    .setRejectCall(false)
                    .setSilenceCall(false)
                    .setSkipCallLog(false)
                    .setSkipNotification(false)
                    .build(),
            )
        }
    }
}
