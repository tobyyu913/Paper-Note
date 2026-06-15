package com.toby.papernote

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.random.Random

/**
 * Runtime-synthesized sounds — no audio assets.
 *  flip(): a band-limited paper rustle.
 *  stud(): a metallic snap for the press stud.
 */
class Sounds {
    private val sr = 44100
    private val rustles = (0..3).map { makeRustle(it.toLong() * 2654435761L) }
    private val snap = makeStud()

    fun flip() = play(rustles.random())
    fun stud() = play(snap)

    private fun play(buf: ShortArray) {
        val track = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(sr)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
            buf.size * 2,
            AudioTrack.MODE_STATIC,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        )
        track.write(buf, 0, buf.size)
        track.notificationMarkerPosition = buf.size
        track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(t: AudioTrack?) { t?.release() }
            override fun onPeriodicNotification(t: AudioTrack?) {}
        })
        track.play()
    }

    private fun makeRustle(seed: Long): ShortArray {
        val n = (sr * 0.26).toInt()
        val out = ShortArray(n)
        val rng = Random(seed)
        var prev = 0f
        for (i in 0 until n) {
            val t = i.toDouble() / n
            val attack = minOf(1.0, t / 0.04)
            val decay = Math.pow(1.0 - t, 1.6)
            var env = (attack * decay).toFloat()
            if (rng.nextFloat() > 0.985f) env *= 1.5f + rng.nextFloat() * 1.1f
            val white = rng.nextFloat() * 2f - 1f
            val hp = white - prev
            prev = white
            out[i] = (hp * env * 0.45f * 32767f).coerceIn(-32767f, 32767f).toInt().toShort()
        }
        return out
    }

    private fun makeStud(): ShortArray {
        val n = (sr * 0.14).toInt()
        val out = ShortArray(n)
        val rng = Random(0xBEEFF00D)
        val clicks = intArrayOf(0, (0.018 * sr).toInt())
        val clickLen = (0.004 * sr).toInt()
        for (i in 0 until n) {
            val t = i.toDouble() / sr
            var s = 0.0
            val ring = sin(2 * PI * 2400 * t) * 0.6 + sin(2 * PI * 3600 * t) * 0.4
            s += ring * exp(-t / 0.02) * 0.35
            for (c in clicks) {
                val d = i - c
                if (d in 0 until clickLen) {
                    val local = d.toDouble() / clickLen
                    s += (rng.nextFloat() * 2f - 1f) * Math.pow(1 - local, 3.0) * 0.8
                }
            }
            out[i] = (s.toFloat().coerceIn(-1f, 1f) * 32767f).toInt().toShort()
        }
        return out
    }
}
