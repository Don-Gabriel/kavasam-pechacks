package app.kavasam.kavasam_mobile

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Continuous, consent-gated speech capture for a tracked call.
 *
 * The microphone is the only source: Android does not let normal apps read the
 * cellular voice stream, so the caller is heard acoustically (speakerphone).
 * Recognition prefers the on-device engine so audio never leaves the phone;
 * only the resulting text is kept, in memory, for the current call.
 */
object CallSpeechCapture {
    const val STATUS_OFF = "off"
    const val STATUS_STARTING = "starting"
    const val STATUS_LISTENING = "listening"
    const val STATUS_UNAVAILABLE = "unavailable"

    private const val MAX_CONSECUTIVE_FAILURES = 6
    private const val RESTART_DELAY_MILLIS = 350L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var useOnDevice = true
    private var consecutiveFailures = 0
    private var status = STATUS_OFF
    private var onUpdate: (() -> Unit)? = null
    private var appContext: Context? = null
    private var pendingSegment = ""

    @Synchronized
    fun status(): String = status

    @Synchronized
    fun isRunning(): Boolean = running

    fun start(context: Context, onUpdate: () -> Unit): Boolean {
        synchronized(this) {
            if (running) return true
            if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                status = STATUS_UNAVAILABLE
                return false
            }
            running = true
            status = STATUS_STARTING
            consecutiveFailures = 0
            useOnDevice = true
            this.onUpdate = onUpdate
            appContext = context.applicationContext
        }
        mainHandler.post { startListening() }
        return true
    }

    fun stop() {
        synchronized(this) {
            if (!running && status == STATUS_OFF) return
            running = false
            status = STATUS_OFF
            onUpdate = null
            appContext = null
            pendingSegment = ""
        }
        mainHandler.post {
            recognizer?.destroy()
            recognizer = null
        }
    }

    // Runs on the main thread: SpeechRecognizer requires it.
    private fun startListening() {
        val context = synchronized(this) { if (running) appContext else null } ?: return
        if (recognizer == null) {
            recognizer = createRecognizer(context) ?: run {
                markUnavailable()
                return
            }
            recognizer?.setRecognitionListener(listener)
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-IN")
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, useOnDevice)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Scam calls in India mix languages; ignored by engines
                // that do not support switching.
                putExtra("android.speech.extra.ENABLE_LANGUAGE_SWITCH", true)
                putStringArrayListExtra(
                    "android.speech.extra.LANGUAGE_SWITCH_ALLOWED_LANGUAGES",
                    arrayListOf("en-IN", "hi-IN", "ta-IN"),
                )
            }
        }
        runCatching { recognizer?.startListening(intent) }.onFailure { recordFailure() }
    }

    private fun createRecognizer(context: Context): SpeechRecognizer? = runCatching {
        if (useOnDevice &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } else {
            SpeechRecognizer.createSpeechRecognizer(context)
        }
    }.getOrNull()

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            val update = synchronized(CallSpeechCapture) {
                if (!running) return
                consecutiveFailures = 0
                if (status != STATUS_LISTENING) {
                    status = STATUS_LISTENING
                    onUpdate
                } else {
                    null
                }
            }
            update?.invoke()
        }

        override fun onResults(results: Bundle?) {
            handleText(results)
            restartSoon()
        }

        override fun onPartialResults(partialResults: Bundle?) = Unit

        override fun onError(error: Int) {
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                -> {
                    synchronized(CallSpeechCapture) { consecutiveFailures = 0 }
                    restartSoon()
                }
                SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
                SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
                -> {
                    // Retry once with the online-capable engine before giving up.
                    val retry = synchronized(CallSpeechCapture) {
                        if (useOnDevice) {
                            useOnDevice = false
                            true
                        } else {
                            false
                        }
                    }
                    if (retry) {
                        mainHandler.post {
                            recognizer?.destroy()
                            recognizer = null
                            startListening()
                        }
                    } else {
                        markUnavailable()
                    }
                }
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> markUnavailable()
                else -> {
                    recordFailure()
                    restartSoon()
                }
            }
        }

        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun handleText(results: Bundle?) {
        val text = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            ?.trim()
            .orEmpty()
        if (text.isEmpty()) return
        val (context, update) = synchronized(this) {
            if (!running) return
            consecutiveFailures = 0
            appContext to onUpdate
        }
        if (context != null) {
            CallSafetyTracker.appendTranscript(context, text)
            update?.invoke()
        }
    }

    private fun recordFailure() {
        val giveUp = synchronized(this) {
            consecutiveFailures += 1
            consecutiveFailures >= MAX_CONSECUTIVE_FAILURES
        }
        if (giveUp) markUnavailable()
    }

    private fun markUnavailable() {
        val update = synchronized(this) {
            running = false
            status = STATUS_UNAVAILABLE
            val value = onUpdate
            onUpdate = null
            value
        }
        mainHandler.post {
            recognizer?.destroy()
            recognizer = null
        }
        update?.invoke()
    }

    private fun restartSoon() {
        mainHandler.postDelayed({
            if (synchronized(this) { running }) startListening()
        }, RESTART_DELAY_MILLIS)
    }
}
