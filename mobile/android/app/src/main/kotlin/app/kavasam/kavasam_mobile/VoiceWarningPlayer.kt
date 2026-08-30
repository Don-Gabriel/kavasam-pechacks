package app.kavasam.kavasam_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import java.io.File
import java.util.Locale

/**
 * Plays spoken scam warnings. The preferred source is ElevenLabs audio synthesised
 * by the gateway; when that is unavailable the device's own text-to-speech engine
 * reads the warning so the user still hears an alert offline.
 */
object VoiceWarningPlayer {
    private var mediaPlayer: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var pendingSpeak: (() -> Unit)? = null

    @Synchronized
    fun playAudio(context: Context, mp3: ByteArray): Boolean {
        if (mp3.isEmpty()) return false
        stop()
        return runCatching {
            val file = File(context.cacheDir, "kavasam_warning.mp3")
            file.writeBytes(mp3)
            val player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                setDataSource(file.absolutePath)
                setOnCompletionListener { mp ->
                    mp.release()
                    synchronized(VoiceWarningPlayer) {
                        if (mediaPlayer === mp) mediaPlayer = null
                    }
                    runCatching { file.delete() }
                }
                prepare()
                start()
            }
            mediaPlayer = player
            true
        }.getOrDefault(false)
    }

    @Synchronized
    fun speak(context: Context, text: String, language: String): Boolean {
        if (text.isBlank()) return false
        val locale = if (language == "ta") Locale("ta", "IN") else Locale.ENGLISH
        val utter = {
            tts?.language = locale
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "kavasam-warning")
            Unit
        }
        if (tts == null) {
            pendingSpeak = utter
            tts = TextToSpeech(context.applicationContext) { status ->
                synchronized(VoiceWarningPlayer) {
                    ttsReady = status == TextToSpeech.SUCCESS
                    if (ttsReady) {
                        pendingSpeak?.invoke()
                    }
                    pendingSpeak = null
                }
            }
            return true
        }
        if (ttsReady) utter() else pendingSpeak = utter
        return true
    }

    @Synchronized
    fun stop() {
        runCatching {
            mediaPlayer?.let { player ->
                if (player.isPlaying) player.stop()
                player.release()
            }
        }
        mediaPlayer = null
        runCatching { tts?.stop() }
    }
}
