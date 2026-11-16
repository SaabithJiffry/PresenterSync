package com.saabithjiffry.presentersync.remote

import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.FormFactorResolver
import com.saabithjiffry.presentersync.remote.network.ConnStatus
import com.saabithjiffry.presentersync.remote.network.ConnectionUiState
import com.saabithjiffry.presentersync.remote.ui.overlay.FloatingMicOverlayManager
import com.saabithjiffry.presentersync.remote.ui.overlay.HudSnakeEngine
import com.saabithjiffry.presentersync.remote.ui.overlay.HudSnakeOverlayManager
import com.saabithjiffry.presentersync.remote.ui.overlay.SnakePhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class HudSnakeInstrumentationTest {

    private fun ensureOverlayPermission(app: PresenterSyncRemoteApp) {
        if (Settings.canDrawOverlays(app)) return
        val cmd = "appops set ${app.packageName} SYSTEM_ALERT_WINDOW allow"
        val pfd: ParcelFileDescriptor = InstrumentationRegistry.getInstrumentation()
            .uiAutomation
            .executeShellCommand(cmd)
        ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes() }
        val deadline = SystemClock.uptimeMillis() + 2000L
        while (!Settings.canDrawOverlays(app) && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(50L)
        }
        assertTrue("SYSTEM_ALERT_WINDOW permission must be granted for overlay test", Settings.canDrawOverlays(app))
    }

    @Test
    fun quickMenuTryAtYourOwnRiskRequiresSustained5SecondHold() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        ensureOverlayPermission(app)
        val instr = InstrumentationRegistry.getInstrumentation()
        val prevCfg = app.configStore.current
        app.configStore.update { it.copy(showIndicator = true, firstRun = false) }

        val launchCount = AtomicInteger(0)
        val launchLatch = CountDownLatch(1)
        val mgrRef = AtomicReference<FloatingMicOverlayManager?>(null)
        val rowRef = AtomicReference<View?>(null)
        val menuRef = AtomicReference<View?>(null)

        try {
            instr.runOnMainSync {
                val mgr = FloatingMicOverlayManager(
                    context = app,
                    configStore = app.configStore,
                    connectionManager = app.connectionManager,
                    onLaunchEasterSnake = {
                        launchCount.incrementAndGet()
                        launchLatch.countDown()
                    }
                )
                mgrRef.set(mgr)
                mgr.showOrUpdate(
                    app.configStore.current,
                    ConnectionUiState(
                        connected = true,
                        connStatus = ConnStatus.CONNECTED,
                        isMuted = true
                    )
                )
                val menu = mgr.openQuickMenuForTesting()
                menuRef.set(menu)
                rowRef.set(menu?.findViewWithTag("quick_menu_easter_row"))
            }

            val menu = menuRef.get()
            val row = rowRef.get()
            assertNotNull("Quick Menu must attach cleanly", menu)
            assertNotNull("Quick Menu must contain quick_menu_easter_row", row)
            val density = app.resources.displayMetrics.density
            assertTrue(
                "Easter row touch target must meet 44dp minimum height",
                row!!.minimumHeight >= (44f * density).toInt() - 1
            )

            // 1. Short tap (<5000ms) MUST NOT trigger Snake
            instr.runOnMainSync {
                val t0 = SystemClock.uptimeMillis()
                val down = MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, 24f, 24f, 0)
                row.dispatchTouchEvent(down)
                down.recycle()
            }
            Thread.sleep(280L)
            instr.runOnMainSync {
                val t1 = SystemClock.uptimeMillis()
                val up = MotionEvent.obtain(t1 - 280L, t1, MotionEvent.ACTION_UP, 24f, 24f, 0)
                row.dispatchTouchEvent(up)
                up.recycle()
            }
            Thread.sleep(200L)
            assertEquals("Short tap must do nothing", 0, launchCount.get())

            // 2. Drag movement > 70dp cancels the hold cleanly before trigger
            instr.runOnMainSync {
                val t0 = SystemClock.uptimeMillis()
                val down = MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, 24f, 24f, 0)
                row.dispatchTouchEvent(down)
                down.recycle()
            }
            Thread.sleep(AppConstants.SECRET_SNAKE_HINT_DELAY_MS + 180L)
            val moveOffsetPx = 85f * density
            instr.runOnMainSync {
                val tMove = SystemClock.uptimeMillis()
                val move = MotionEvent.obtain(tMove - 1000L, tMove, MotionEvent.ACTION_MOVE, 24f + moveOffsetPx, 24f, 0)
                row.dispatchTouchEvent(move)
                move.recycle()
                val up = MotionEvent.obtain(tMove - 1000L, tMove + 10L, MotionEvent.ACTION_UP, 24f + moveOffsetPx, 24f, 0)
                row.dispatchTouchEvent(up)
                up.recycle()
            }
            Thread.sleep(200L)
            assertEquals("Dragging off row must cancel Snake hold", 0, launchCount.get())

            // 3. Sustained >= 5000ms hold launches Snake cleanly
            val downTime = SystemClock.uptimeMillis()
            instr.runOnMainSync {
                val down = MotionEvent.obtain(downTime, downTime, MotionEvent.ACTION_DOWN, 24f, 24f, 0)
                row.dispatchTouchEvent(down)
                down.recycle()
            }
            val triggered = launchLatch.await(AppConstants.SECRET_SNAKE_HOLD_MS + 1800L, TimeUnit.MILLISECONDS)
            assertTrue("Holding 'Try at your own risk' for 5 seconds must launch Easter Snake", triggered)
            assertEquals("Sustained 5s hold must fire exactly once", 1, launchCount.get())

            instr.runOnMainSync {
                val up = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), MotionEvent.ACTION_UP, 24f, 24f, 0)
                row.dispatchTouchEvent(up)
                up.recycle()
            }
        } finally {
            instr.runOnMainSync {
                mgrRef.get()?.dismissQuickMenuForTesting()
                mgrRef.get()?.hide()
            }
            app.configStore.update { prevCfg }
        }
    }

    @Test
    fun snakeOverlayAttachesFocusableWindowRespondsToSwipeKeyboardDpadAndRestoresPillCleanly() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        ensureOverlayPermission(app)
        val instr = InstrumentationRegistry.getInstrumentation()
        val prevCfg = app.configStore.current
        app.configStore.update { it.copy(showIndicator = true, firstRun = false) }

        val overlayMgrRef = AtomicReference<FloatingMicOverlayManager?>(null)
        val snakeMgrRef = AtomicReference<HudSnakeOverlayManager?>(null)

        try {
            instr.runOnMainSync {
                lateinit var overlayMgr: FloatingMicOverlayManager
                val snakeMgr = HudSnakeOverlayManager(
                    context = app,
                    configStore = app.configStore,
                    onActiveChanged = { active -> overlayMgr.setHiddenForEasterEgg(active) }
                )
                overlayMgr = FloatingMicOverlayManager(
                    context = app,
                    configStore = app.configStore,
                    connectionManager = app.connectionManager,
                    onLaunchEasterSnake = {
                        val rect = overlayMgr.currentPillRectPx()
                        snakeMgr.start(
                            cfg = app.configStore.current,
                            isMuted = true,
                            pillLeftScreenPx = rect.left,
                            pillTopScreenPx = rect.top,
                            pillWidthPx = rect.width(),
                            pillHeightPx = rect.height(),
                            skipMorph = false
                        )
                    }
                )
                overlayMgrRef.set(overlayMgr)
                snakeMgrRef.set(snakeMgr)

                overlayMgr.showOrUpdate(
                    app.configStore.current,
                    ConnectionUiState(connected = true, connStatus = ConnStatus.CONNECTED, isMuted = true)
                )
                val rect = overlayMgr.currentPillRectPx()
                val started = snakeMgr.start(
                    cfg = app.configStore.current,
                    isMuted = true,
                    pillLeftScreenPx = rect.left,
                    pillTopScreenPx = rect.top,
                    pillWidthPx = rect.width(),
                    pillHeightPx = rect.height(),
                    skipMorph = false
                )
                assertTrue("HudSnakeOverlayManager.start() must succeed", started)
                assertTrue("Overlay must enter active state", snakeMgr.isActive)
                assertTrue("Mic pill must hide while Snake is active", overlayMgr.isHiddenForEasterEggForTesting())
                val view = snakeMgr.viewForTesting()
                assertNotNull("Snake overlay view must be attached", view)
                val lp = view!!.layoutParams as WindowManager.LayoutParams
                assertEquals(
                    "Snake overlay must stay focusable for hardware Keyboard/D-Pad/Back keys",
                    0,
                    lp.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                )
            }

            // Wait for 360ms pill morph to complete into PLAYING
            Thread.sleep(460L)
            instr.runOnMainSync {
                val snakeMgr = snakeMgrRef.get()!!
                val view = snakeMgr.viewForTesting()!!
                assertEquals(SnakePhase.PLAYING, snakeMgr.engine.phase)

                // Touch swipe gesture (Up)
                val t0 = SystemClock.uptimeMillis()
                val evDown = MotionEvent.obtain(t0, t0, MotionEvent.ACTION_DOWN, 220f, 360f, 0)
                val evMove = MotionEvent.obtain(t0, t0 + 30L, MotionEvent.ACTION_MOVE, 220f, 160f, 0)
                val evUp = MotionEvent.obtain(t0, t0 + 50L, MotionEvent.ACTION_UP, 220f, 160f, 0)
                view.onTouchEvent(evDown)
                view.onTouchEvent(evMove)
                view.onTouchEvent(evUp)
                evDown.recycle()
                evMove.recycle()
                evUp.recycle()

                // Hardware Keyboard & D-Pad keys: Edge toggle (E), Pause/Resume (P), Exit (BACK)
                val edgeBefore = snakeMgr.engine.edgeWrap
                assertTrue(view.onKeyDown(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DPAD_RIGHT)))
                assertTrue(view.onKeyDown(KeyEvent.KEYCODE_E, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_E)))
                assertEquals(!edgeBefore, snakeMgr.engine.edgeWrap)

                assertTrue(view.onKeyDown(KeyEvent.KEYCODE_P, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_P)))
                assertEquals(SnakePhase.PAUSED, snakeMgr.engine.phase)
                assertTrue(view.onKeyDown(KeyEvent.KEYCODE_P, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_P)))
                assertEquals(SnakePhase.PLAYING, snakeMgr.engine.phase)

                assertTrue(view.onKeyDown(KeyEvent.KEYCODE_BACK, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
            }

            instr.runOnMainSync {
                val snakeMgr = snakeMgrRef.get()!!
                val overlayMgr = overlayMgrRef.get()!!
                assertFalse("Back key must exit Snake cleanly", snakeMgr.isActive)
                assertFalse("Exiting Snake must unhide Mic pill flag", overlayMgr.isHiddenForEasterEggForTesting())
                assertTrue("Mic pill view must remain restored", overlayMgr.isPillAttachedForTesting())
            }
        } finally {
            instr.runOnMainSync {
                snakeMgrRef.get()?.stop()
                overlayMgrRef.get()?.hide()
            }
            app.configStore.update { prevCfg }
        }
    }

    @Test
    fun phoneAndSmartBoardResponsiveGridsAndHighScorePersistence() {
        val app = ApplicationProvider.getApplicationContext<PresenterSyncRemoteApp>()
        val prevCfg = app.configStore.current
        try {
            val phoneFf = FormFactorResolver.resolve(DeviceProfileMode.PHONE, 360, 760, 360)
            val boardFf = FormFactorResolver.resolve(DeviceProfileMode.SMART_BOARD, 1920, 1080, 1080)
            val phoneGrid = HudSnakeEngine.computeGridMetrics(1080, 2280, 3.0f, phoneFf, 1.0f)
            val boardGrid = HudSnakeEngine.computeGridMetrics(3840, 2160, 2.0f, boardFf, 1.0f)

            assertTrue("Portrait Phone must use compact 2-row scoreboard", phoneGrid.isCompactScoreboard)
            assertEquals(4, phoneGrid.sbSafeRows)
            assertFalse("Smart Board must use wide single-row explorer scoreboard", boardGrid.isCompactScoreboard)
            assertEquals(2, boardGrid.sbSafeRows)
            assertTrue("Smart Board grid must keep playable columns", boardGrid.cols >= 16 && boardGrid.rows >= 10)

            app.configStore.update { it.copy(snakeHighScore = 0) }
            app.configStore.updateSnakeHighScore(420)
            assertEquals(420, app.configStore.current.snakeHighScore)
            app.configStore.updateSnakeHighScore(150)
            assertEquals("Lower score must never overwrite higher best score", 420, app.configStore.current.snakeHighScore)
        } finally {
            app.configStore.update { prevCfg }
        }
    }
}
