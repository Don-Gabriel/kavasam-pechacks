package app.kavasam.kavasam_mobile

import android.content.Intent
import android.os.IBinder
import android.telecom.Call
import android.telecom.InCallService

class KavasamInCallService : InCallService() {
    override fun onBind(intent: Intent?): IBinder? {
        PhoneCallController.attach(this)
        return super.onBind(intent)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        PhoneCallController.detach(this)
        return super.onUnbind(intent)
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        PhoneCallController.onCallAdded(this, call)
        openCallScreen()
    }

    override fun onCallRemoved(call: Call) {
        PhoneCallController.onCallRemoved(this, call)
        super.onCallRemoved(call)
    }

    override fun onBringToForeground(showDialpad: Boolean) {
        openCallScreen()
    }

    private fun openCallScreen() {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                action = ACTION_SHOW_CALL
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
        )
    }

    companion object {
        const val ACTION_SHOW_CALL = "app.kavasam.action.SHOW_CALL"
    }
}
