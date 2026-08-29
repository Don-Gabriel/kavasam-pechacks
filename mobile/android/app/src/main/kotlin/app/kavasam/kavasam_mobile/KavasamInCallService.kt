package app.kavasam.kavasam_mobile

import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.OutcomeReceiver
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.telecom.CallEndpointException
import android.telecom.InCallService

class KavasamInCallService : InCallService() {
    private var routeBeforeSpeaker = CallAudioState.ROUTE_EARPIECE
    private var endpointBeforeSpeaker: CallEndpoint? = null
    private var availableEndpoints: List<CallEndpoint> = emptyList()
    private var endpointMuted = false

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

    @Suppress("DEPRECATION")
    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        if (audioState.route != CallAudioState.ROUTE_SPEAKER) {
            routeBeforeSpeaker = audioState.route
        }
        PhoneCallController.onAudioStateChanged()
    }

    override fun onCallEndpointChanged(callEndpoint: CallEndpoint) {
        super.onCallEndpointChanged(callEndpoint)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            callEndpoint.endpointType != CallEndpoint.TYPE_SPEAKER
        ) {
            endpointBeforeSpeaker = callEndpoint
        }
        PhoneCallController.onAudioStateChanged()
    }

    override fun onAvailableCallEndpointsChanged(availableEndpoints: List<CallEndpoint>) {
        super.onAvailableCallEndpointsChanged(availableEndpoints)
        this.availableEndpoints = availableEndpoints.toList()
        PhoneCallController.onAudioStateChanged()
    }

    override fun onMuteStateChanged(isMuted: Boolean) {
        super.onMuteStateChanged(isMuted)
        endpointMuted = isMuted
        PhoneCallController.onAudioStateChanged()
    }

    override fun onBringToForeground(showDialpad: Boolean) {
        openCallScreen()
    }

    @Suppress("DEPRECATION")
    fun setMutedSafely(value: Boolean): Boolean {
        val current = isMutedNow()
        if (current == value) return true
        setMuted(value)
        return true
    }

    @Suppress("DEPRECATION")
    fun isMutedNow(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            endpointMuted
        } else {
            callAudioState?.isMuted ?: false
        }

    @Suppress("DEPRECATION")
    fun isSpeakerOnNow(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            currentCallEndpoint.endpointType == CallEndpoint.TYPE_SPEAKER
        } else {
            (callAudioState?.route ?: 0) and CallAudioState.ROUTE_SPEAKER != 0
        }

    @Suppress("DEPRECATION")
    fun setSpeakerSafely(value: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return setSpeakerEndpoint(value)
        }
        val state = callAudioState ?: return false
        val speakerActive = state.route and CallAudioState.ROUTE_SPEAKER != 0
        if (speakerActive == value) return true
        if (value) {
            if (!speakerActive) routeBeforeSpeaker = state.route
            setAudioRoute(CallAudioState.ROUTE_SPEAKER)
            return true
        }
        val supported = state.supportedRouteMask
        val restore = routeBeforeSpeaker.takeIf {
            it != CallAudioState.ROUTE_SPEAKER && supported and it != 0
        } ?: listOf(
            CallAudioState.ROUTE_BLUETOOTH,
            CallAudioState.ROUTE_WIRED_HEADSET,
            CallAudioState.ROUTE_EARPIECE,
        ).firstOrNull { supported and it != 0 } ?: CallAudioState.ROUTE_EARPIECE
        setAudioRoute(restore)
        return true
    }

    private fun setSpeakerEndpoint(value: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        val current = currentCallEndpoint
        val speakerActive = current.endpointType == CallEndpoint.TYPE_SPEAKER
        if (speakerActive == value) return true
        if (value) endpointBeforeSpeaker = current
        val target = if (value) {
            availableEndpoints.firstOrNull { it.endpointType == CallEndpoint.TYPE_SPEAKER }
        } else {
            endpointBeforeSpeaker?.takeIf { previous ->
                previous.endpointType != CallEndpoint.TYPE_SPEAKER &&
                    availableEndpoints.any { it.identifier == previous.identifier }
            } ?: listOf(
                CallEndpoint.TYPE_BLUETOOTH,
                CallEndpoint.TYPE_WIRED_HEADSET,
                CallEndpoint.TYPE_EARPIECE,
            ).firstNotNullOfOrNull { type ->
                availableEndpoints.firstOrNull { it.endpointType == type }
            }
        } ?: return false
        requestCallEndpointChange(
            target,
            mainExecutor,
            object : OutcomeReceiver<Void?, CallEndpointException> {
                override fun onResult(result: Void?) {
                    PhoneCallController.onAudioStateChanged()
                }

                override fun onError(error: CallEndpointException) {
                    PhoneCallController.onAudioStateChanged()
                }
            },
        )
        return true
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
