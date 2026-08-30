package app.kavasam.kavasam_mobile

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Kavasam Link: an in-app call between two Kavasam phones, relayed by the
 * gateway. The app owns the audio path, so live transcription and scam
 * analysis work without speakerphone tricks - unlike cellular calls, where
 * Android silences microphone capture for normal apps.
 */
object LinkCallEngine {
    private const val SAMPLE_RATE = 16000
    private const val FRAME_BYTES = 3200 // 100 ms of PCM16 mono
    private const val MAX_TRANSCRIPT_ENTRIES = 40

    private val mainHandler = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder()
        .pingInterval(15, TimeUnit.SECONDS)
        .build()

    private var appContext: Context? = null
    private var webSocket: WebSocket? = null
    private var recordThread: Thread? = null
    private var recorder: AudioRecord? = null
    private var player: AudioTrack? = null
    private var echoCanceler: AcousticEchoCanceler? = null

    private var status = "idle" // idle|connecting|waiting|active|ended|failed
    private var role = "host"
    private var code = ""
    private var muted = false
    private var speakerOn = false
    private var peerPresent = false
    private var failure = ""
    private val transcriptEntries = mutableListOf<Pair<String, String>>()
    private var eventSink: EventChannel.EventSink? = null
    private var previousAudioMode = AudioManager.MODE_NORMAL

    @Synchronized
    fun setEventSink(value: EventChannel.EventSink?) {
        eventSink = value
        emit()
    }

    @Synchronized
    fun start(context: Context, wsUrl: String, linkCode: String, linkRole: String): Boolean {
        if (status == "connecting" || status == "waiting" || status == "active") return false
        appContext = context.applicationContext
        role = if (linkRole == "guest") "guest" else "host"
        code = linkCode
        muted = false
        speakerOn = false
        peerPresent = false
        failure = ""
        transcriptEntries.clear()
        status = "connecting"
        CallSafetyTracker.onCallStarted(context, "Kavasam Link")
        CallSafetyTracker.setEnabled(
            context,
            true,
            CallerIdentityStore.assess(context, "Kavasam Link", "link"),
        )
        CallSafetyTracker.setAudioCaptured(true)
        val request = Request.Builder().url(wsUrl).build()
        webSocket = client.newWebSocket(request, listener)
        emit()
        return true
    }

    @Synchronized
    fun end(): Boolean {
        if (status == "idle") return false
        runCatching { webSocket?.send("""{"type":"bye"}""") }
        finish("ended")
        return true
    }

    @Synchronized
    fun setMuted(value: Boolean): Boolean {
        muted = value
        emit()
        return true
    }

    @Synchronized
    fun setSpeaker(context: Context, value: Boolean): Boolean {
        speakerOn = value
        applySpeaker(context, value)
        emit()
        return true
    }

    @Synchronized
    fun addSignal(context: Context, signal: String): Boolean {
        if (status != "active" && status != "waiting") return false
        val added = CallSafetyTracker.addSignal(context, signal)
        if (added) emit()
        return added
    }

    @Synchronized
    fun snapshot(): Map<String, Any?> = mapOf(
        "status" to status,
        "role" to role,
        "code" to code,
        "muted" to muted,
        "speakerOn" to speakerOn,
        "peerPresent" to peerPresent,
        "failure" to failure,
        "entries" to transcriptEntries.map { (speaker, text) ->
            mapOf("speaker" to speaker, "text" to text)
        },
    ) + CallSafetyTracker.snapshot()

    private val listener = object : WebSocketListener() {
        override fun onMessage(webSocket: WebSocket, text: String) {
            val payload = runCatching { JSONObject(text) }.getOrNull() ?: return
            when (payload.optString("type")) {
                "joined" -> synchronized(LinkCallEngine) {
                    peerPresent = payload.optBoolean("peerPresent", false)
                    status = if (peerPresent) "active" else "waiting"
                    if (peerPresent) startAudio()
                    emit()
                }
                "peer-joined" -> synchronized(LinkCallEngine) {
                    peerPresent = true
                    status = "active"
                    startAudio()
                    emit()
                }
                "peer-left" -> synchronized(LinkCallEngine) {
                    if (status == "active" || status == "waiting") {
                        finish("ended")
                    }
                }
                "transcript" -> handleTranscript(
                    payload.optString("role"),
                    payload.optString("text"),
                )
            }
        }

        override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
            player?.let { track ->
                runCatching { track.write(bytes.toByteArray(), 0, bytes.size) }
            }
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            synchronized(LinkCallEngine) {
                if (status != "idle" && status != "ended") {
                    failure = t.message ?: "The link connection failed."
                    finish("failed")
                }
            }
        }

        override fun onClosed(webSocket: WebSocket, codeValue: Int, reason: String) {
            synchronized(LinkCallEngine) {
                if (status == "connecting") {
                    failure = "The link code was not accepted."
                    finish("failed")
                } else if (status != "idle") {
                    finish("ended")
                }
            }
        }
    }

    private fun handleTranscript(speakerRole: String, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        val (context, speaker) = synchronized(this) {
            if (status != "active" && status != "waiting") return
            val label = if (speakerRole == role) "You" else "Caller"
            transcriptEntries += label to trimmed
            while (transcriptEntries.size > MAX_TRANSCRIPT_ENTRIES) {
                transcriptEntries.removeAt(0)
            }
            appContext to label
        }
        if (context != null) {
            // Feed only the remote side into risk keywords: the caller's words
            // are the scam evidence, and the user's own speech stays out.
            if (speaker == "Caller") {
                CallSafetyTracker.appendTranscript(context, trimmed)
            }
        }
        synchronized(this) { emit() }
    }

    @SuppressLint("MissingPermission")
    private fun startAudio() {
        if (recordThread != null) return
        val context = appContext ?: return
        val audioManager = context.getSystemService(AudioManager::class.java)
        previousAudioMode = audioManager.mode
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        applySpeaker(context, speakerOn)

        val minRecord = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minRecord, FRAME_BYTES * 2),
        )
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            failure = "The microphone could not be opened."
            finish("failed")
            return
        }
        if (AcousticEchoCanceler.isAvailable()) {
            echoCanceler = runCatching {
                AcousticEchoCanceler.create(record.audioSessionId)?.apply { enabled = true }
            }.getOrNull()
        }
        recorder = record

        val minTrack = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        player = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(SAMPLE_RATE)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .build(),
            maxOf(minTrack, FRAME_BYTES * 4),
            AudioTrack.MODE_STREAM,
            record.audioSessionId,
        ).also { it.play() }

        record.startRecording()
        recordThread = Thread({
            val frame = ByteArray(FRAME_BYTES)
            while (!Thread.currentThread().isInterrupted) {
                val read = try {
                    record.read(frame, 0, frame.size)
                } catch (_: Throwable) {
                    break
                }
                if (read <= 0) continue
                val socket = webSocket ?: break
                val silenced = synchronized(this) { muted }
                if (!silenced) {
                    socket.send(frame.copyOf(read).toByteString())
                }
            }
        }, "kavasam-link-audio").also { it.start() }
    }

    private fun applySpeaker(context: Context, value: Boolean) {
        val audioManager = context.getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val target = audioManager.availableCommunicationDevices.firstOrNull {
                if (value) {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                } else {
                    it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
            }
            if (target != null) {
                runCatching { audioManager.setCommunicationDevice(target) }
                return
            }
        }
        @Suppress("DEPRECATION")
        audioManager.isSpeakerphoneOn = value
    }

    // Callers hold the LinkCallEngine lock.
    private fun finish(finalStatus: String) {
        status = finalStatus
        peerPresent = false
        recordThread?.interrupt()
        recordThread = null
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        echoCanceler?.release()
        echoCanceler = null
        runCatching { player?.stop() }
        player?.release()
        player = null
        webSocket?.close(1000, "done")
        webSocket = null
        appContext?.let { context ->
            val audioManager = context.getSystemService(AudioManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                runCatching { audioManager.clearCommunicationDevice() }
            }
            audioManager.mode = previousAudioMode
            CallSafetyTracker.finishCall(context)
        }
        emit()
        appContext = null
    }

    private fun emit() {
        val value = runCatching { snapshot() }.getOrNull()
        val sink = eventSink
        val send = { sink?.success(value) }
        if (Looper.myLooper() == Looper.getMainLooper()) send() else mainHandler.post { send() }
    }
}
