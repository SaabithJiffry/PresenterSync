package com.saabithjiffry.presentersync.remote.service

import android.content.Context
import android.content.Intent
import android.media.VolumeProvider
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.view.KeyEvent
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.input.BubbleGestureAction

class BackgroundMediaActionDebouncer(
    private val debounceMs: Long = AppConstants.CLICKER_DEBOUNCE_MS,
    private val clockMs: () -> Long = { System.currentTimeMillis() }
) {
    private var lastAction: BubbleGestureAction? = null
    private var lastActionAtMs: Long = -debounceMs

    @Synchronized
    fun shouldDispatch(action: BubbleGestureAction): Boolean {
        val now = clockMs()
        if (action == lastAction && (now - lastActionAtMs) < debounceMs) {
            return false
        }
        lastAction = action
        lastActionAtMs = now
        return true
    }

    @Synchronized
    fun reset() {
        lastAction = null
        lastActionAtMs = -debounceMs
    }
}

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
    debounceMs: Long = AppConstants.CLICKER_DEBOUNCE_MS,
    clockMs: () -> Long = { System.currentTimeMillis() },
    private val onAction: (BubbleGestureAction) -> Unit
) {
    private val appContext = context.applicationContext
    private val debouncer = BackgroundMediaActionDebouncer(debounceMs, clockMs)
    private var mediaSession: MediaSession? = null
    private var currentConfig: RemoteConfig = RemoteConfig()

    private fun dispatchDebounced(action: BubbleGestureAction) {
        if (debouncer.shouldDispatch(action)) {
            onAction(action)
        }
    }

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

                    val action = BackgroundMediaKeyMapper.resolveKeyAction(keyEvent.keyCode, currentConfig)
                    if (action != null) {
                        if (keyEvent.action == KeyEvent.ACTION_DOWN && keyEvent.repeatCount == 0) {
                            dispatchDebounced(action)
                        }
                        return true
                    }
                    return super.onMediaButtonEvent(mediaButtonIntent)
                }

                override fun onPlay() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PLAY, currentConfig)?.let(::dispatchDebounced)
                }

                override fun onPause() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PAUSE, currentConfig)?.let(::dispatchDebounced)
                }

                override fun onSkipToNext() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_NEXT, currentConfig)?.let(::dispatchDebounced)
                }

                override fun onSkipToPrevious() {
                    BackgroundMediaKeyMapper.resolveKeyAction(KeyEvent.KEYCODE_MEDIA_PREVIOUS, currentConfig)?.let(::dispatchDebounced)
                }
            })

            val volumeProvider = object : VolumeProvider(VOLUME_CONTROL_RELATIVE, 100, 50) {
                override fun onAdjustVolume(direction: Int) {
                    val action = BackgroundMediaKeyMapper.resolveVolumeStepAction(direction, currentConfig)
                    if (action != null) {
                        dispatchDebounced(action)
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
        debouncer.reset()
        val session = mediaSession ?: return
        mediaSession = null
        try {
            session.isActive = false
            session.release()
        } catch (_: Exception) {
        }
    }
}
