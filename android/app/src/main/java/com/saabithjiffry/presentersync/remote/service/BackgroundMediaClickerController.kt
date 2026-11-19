package com.saabithjiffry.presentersync.remote.service

import android.content.Context
import android.content.Intent
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction

object BackgroundMediaKeyMapper {
    fun resolveKeyAction(keyCode: Int, config: RemoteConfig): BubbleGestureAction? {
        if (!config.enableBackgroundMediaClicker) return null
        val primary = when (config.backgroundMediaPrimaryAction) {
            BubbleGestureAction.TRANSITION_SCENE -> BubbleGestureAction.TRANSITION_SCENE
            else -> BubbleGestureAction.TOGGLE_MUTE
        }
        return when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_HEADSETHOOK,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE -> primary
            KeyEvent.KEYCODE_MEDIA_NEXT -> BubbleGestureAction.SLIDE_NEXT
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> BubbleGestureAction.SLIDE_PREV
            else -> null
        }
    }

    fun resolveVolumeStepAction(direction: Int, config: RemoteConfig): BubbleGestureAction? {
        if (!config.enableBackgroundMediaClicker || direction == 0) return null
        return if (direction > 0) BubbleGestureAction.SLIDE_NEXT else BubbleGestureAction.SLIDE_PREV
    }
}

class BackgroundMediaClickerController(
    context: Context,
    private val onAction: (BubbleGestureAction) -> Unit
) {
    private val appContext = context.applicationContext
    private var mediaSession: MediaSession? = null
    private var currentConfig: RemoteConfig = RemoteConfig()

    fun update(config: RemoteConfig) {
        currentConfig = config
        if (config.enableBackgroundMediaClicker) {
            ensureSessionActive()
        } else {
            release()
        }
    }

    private fun ensureSessionActive() {
        if (mediaSession != null) {
            mediaSession?.isActive = true
            return
        }
        try {
            val session = MediaSession(appContext, "PresenterSyncMediaClicker")
            session.setCallback(object : MediaSession.Callback() {
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val keyEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonIntent.getParcelableExtra(Intent.EXTRA_KEY_EVENT)
                    } ?: return super.onMediaButtonEvent(mediaButtonIntent)

                    if (keyEvent.action == KeyEvent.ACTION_DOWN && keyEvent.repeatCount == 0) {
                        val action = BackgroundMediaKeyMapper.resolveKeyAction(keyEvent.keyCode, currentConfig)
                        if (action != null) {
                            onAction(action)
                            return true
                        }
                    }
                    return super.onMediaButtonEvent(mediaButtonIntent)
                }

                override fun onPlay() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY, currentConfig)?.let(onAction)
                }

                override fun onPause() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PAUSE, currentConfig)?.let(onAction)
                }

                override fun onSkipToNext() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_NEXT, currentConfig)?.let(onAction)
                }

                override fun onSkipToPrevious() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PREVIOUS, currentConfig)?.let(onAction)
                }
            })

            val volumeProvider = object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    val action = BackgroundMediaKeyMapper.resolveVolumeStepAction(direction, currentConfig)
                    if (action != null) {
                        onAction(action)
                    }
                }
            }
            session.setPlaybackToRemote(volumeProvider)

            val playbackState = PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS
                )
                .setState(PlaybackState.STATE_PLAYING, 0L, 1.0f)
                .build()
            session.setPlaybackState(playbackState)
            session.isActive = true
            mediaSession = session
        } catch (_: Exception) {
        }
    }

    fun release() {
        val session = mediaSession ?: return
        mediaSession = null
        try {
            session.isActive = false
            session.release()
        } catch (_: Exception) {
        }
    }
}
