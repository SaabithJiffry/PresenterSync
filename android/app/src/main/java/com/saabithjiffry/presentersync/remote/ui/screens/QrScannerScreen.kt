package com.saabithjiffry.presentersync.remote.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.util.Size
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FlashOff
import androidx.compose.material.icons.filled.FlashOn
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import androidx.core.content.ContextCompat
import com.saabithjiffry.presentersync.remote.config.DeepLinkParser
import com.saabithjiffry.presentersync.remote.config.DeviceProfileMode
import com.saabithjiffry.presentersync.remote.config.ParsedConnectionPayload
import com.saabithjiffry.presentersync.remote.config.QrImageDecoder
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

@Composable
fun QrScannerDialog(
    onPayloadScanned: (ParsedConnectionPayload) -> Unit,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val formFactor = rememberFormFactor(DeviceProfileMode.AUTO)
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED
        )
    }
    var cameraError by remember { mutableStateOf<String?>(null) }
    var manualUri by remember { mutableStateOf("") }
    var pasteError by remember { mutableStateOf<String?>(null) }
    var scanWarning by remember { mutableStateOf<String?>(null) }
    var lastWarnMs by remember { mutableStateOf(0L) }

    val permLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
    }

    val galleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        pasteError = null
        scanWarning = null
        scope.launch {
            val decoded = withContext(Dispatchers.IO) {
                runCatching { QrImageDecoder.decodeUri(context, uri) }.getOrNull()
            }
            if (decoded.isNullOrBlank()) {
                pasteError = "No QR code detected inside the selected image."
                return@launch
            }
            val parsed = DeepLinkParser.parse(decoded)
            if (parsed == null) {
                pasteError = "QR code found, but it is not a PresenterSync pairing code."
                return@launch
            }
            haptic.performHapticFeedback(HapticFeedbackType.LongPress)
            if (parsed.requiresRelayPassword) {
                Toast.makeText(context, "Imported! Enter your Relay Password to connect.", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(context, "Pairing QR imported!", Toast.LENGTH_SHORT).show()
            }
            onPayloadScanned(parsed)
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, securePolicy = SecureFlagPolicy.SecureOn)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 560.dp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 14.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.background,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline)
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Pinned Explorer Header
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = 18.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        modifier = Modifier.weight(1f)
                    ) {
                        Icon(
                            imageVector = Icons.Default.QrCodeScanner,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Column {
                            Text(
                                text = "Scan PresenterSync Host QR",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            Text(
                                text = "Zero-GMS CameraX + ZXing offline decoder",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "Close Scanner")
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(18.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    if (!hasCameraPermission) {
                        ExplorerCard(contentPadding = 16) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    text = "Camera Permission Needed for QR Scan",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text(
                                    text = "Grant Camera access to scan the QR shown in PresenterSync Host -> Settings -> Remote Companion Info. If your Smart Board lacks a camera, paste the URI below or use the 6-char Session Code instead.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Button(
                                    onClick = { permLauncher.launch(Manifest.permission.CAMERA) },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Icon(Icons.Default.CameraAlt, contentDescription = null)
                                    Spacer(Modifier.width(8.dp))
                                    Text("Allow Camera Access")
                                }
                                OutlinedButton(
                                    onClick = { galleryLauncher.launch("image/*") },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Icon(Icons.Default.PhotoLibrary, contentDescription = null)
                                    Spacer(Modifier.width(8.dp))
                                    Text("Import QR Image (Gallery)")
                                }
                            }
                        }
                    } else if (cameraError != null) {
                        ExplorerCard(
                            contentPadding = 16,
                            borderColor = Color(0xFFD97706).copy(alpha = 0.6f)
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Text(
                                    text = cameraError.orEmpty(),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = Color(0xFFD97706)
                                )
                                OutlinedButton(
                                    onClick = { galleryLauncher.launch("image/*") },
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Icon(Icons.Default.PhotoLibrary, contentDescription = null)
                                    Spacer(Modifier.width(8.dp))
                                    Text("Import QR Image (Gallery)")
                                }
                            }
                        }
                    } else {
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.primary),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(if (formFactor.isCompactHeight) 180.dp else 260.dp)
                        ) {
                            Box(modifier = Modifier.fillMaxSize()) {
                                CameraQrPreviewBox(
                                    lifecycleOwner = lifecycleOwner,
                                    onDecoded = { payload ->
                                        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                                        if (payload.requiresRelayPassword) {
                                            Toast.makeText(
                                                context,
                                                "QR scanned! Enter Relay Password to connect.",
                                                Toast.LENGTH_LONG
                                            ).show()
                                        }
                                        onPayloadScanned(payload)
                                    },
                                    onUnrecognizedQr = {
                                        val now = System.currentTimeMillis()
                                        if (now - lastWarnMs > 3000L) {
                                            lastWarnMs = now
                                            scanWarning = "Recognized a QR code, but it is not a PresenterSync pairing link."
                                        }
                                    },
                                    onCameraUnavailable = { err ->
                                        cameraError = err
                                    }
                                )
                            }
                        }
                        if (scanWarning != null) {
                            Text(
                                text = scanWarning.orEmpty(),
                                style = MaterialTheme.typography.bodySmall,
                                color = Color(0xFFD97706)
                            )
                        }
                        OutlinedButton(
                            onClick = { galleryLauncher.launch("image/*") },
                            modifier = Modifier.fillMaxWidth(),
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            Icon(Icons.Default.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Import QR Image (Gallery)")
                        }
                    }

                    ExplorerCard(contentPadding = 14) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                text = "Or Paste presentersync://connect Link",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold
                            )
                            OutlinedTextField(
                                value = manualUri,
                                onValueChange = {
                                    manualUri = it
                                    pasteError = null
                                },
                                label = { Text("Pairing URI / JSON") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            if (pasteError != null) {
                                Text(
                                    text = pasteError.orEmpty(),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error
                                )
                            }
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                OutlinedButton(
                                    onClick = onDismiss,
                                    contentPadding = CompactExplorerButtonPadding,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text(
                                        if (formFactor.isTightWidth) "Session Code" else "Use Session Code",
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                                Button(
                                    onClick = {
                                        val parsed = DeepLinkParser.parse(manualUri)
                                        if (parsed == null) {
                                            pasteError = "Invalid pairing URI (expected presentersync://connect?...)"
                                        } else {
                                            onPayloadScanned(parsed)
                                        }
                                    },
                                    contentPadding = CompactExplorerButtonPadding,
                                    modifier = Modifier.weight(1f)
                                ) {
                                    Text("Apply URI", maxLines = 1, softWrap = false)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CameraQrPreviewBox(
    lifecycleOwner: androidx.lifecycle.LifecycleOwner,
    onDecoded: (ParsedConnectionPayload) -> Unit,
    onUnrecognizedQr: () -> Unit,
    onCameraUnavailable: (String) -> Unit
) {
    val context = LocalContext.current
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val handled = remember { AtomicBoolean(false) }
    val analysisExecutor = remember { Executors.newSingleThreadExecutor() }
    val reader = remember { QrImageDecoder.createQrReader() }

    var boundCamera by remember { mutableStateOf<Camera?>(null) }
    var hasFlash by remember { mutableStateOf(false) }
    var torchEnabled by remember { mutableStateOf(false) }
    var currentZoomRatio by remember { mutableStateOf(1.0f) }
    var maxZoomRatio by remember { mutableStateOf(4.0f) }
    var focusReticle by remember { mutableStateOf<Offset?>(null) }

    LaunchedEffect(focusReticle) {
        if (focusReticle != null) {
            delay(900L)
            focusReticle = null
        }
    }

    DisposableEffect(lifecycleOwner) {
        val future = ProcessCameraProvider.getInstance(context)
        val mainExec = ContextCompat.getMainExecutor(context)
        val listener = Runnable {
            runCatching {
                val provider = future.get()
                val selector = when {
                    provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                    provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) -> CameraSelector.DEFAULT_FRONT_CAMERA
                    else -> {
                        onCameraUnavailable("No camera hardware detected on this Smart Board. Use Import QR Image, paste URI, or 6-char Session Code below.")
                        return@Runnable
                    }
                }

                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

                val resolutionSelector = ResolutionSelector.Builder()
                    .setResolutionStrategy(
                        ResolutionStrategy(
                            Size(1280, 720),
                            ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                        )
                    )
                    .build()

                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(resolutionSelector)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                analysis.setAnalyzer(analysisExecutor) { image ->
                    try {
                        if (handled.get()) return@setAnalyzer
                        val decoded = QrImageDecoder.decodeImageProxy(image, reader)
                        if (decoded != null) {
                            val parsed = DeepLinkParser.parse(decoded)
                            if (parsed != null && handled.compareAndSet(false, true)) {
                                mainExec.execute { onDecoded(parsed) }
                            } else if (parsed == null) {
                                mainExec.execute { onUnrecognizedQr() }
                            }
                        }
                    } finally {
                        image.close()
                    }
                }

                provider.unbindAll()
                val cam = provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
                boundCamera = cam
                hasFlash = cam.cameraInfo.hasFlashUnit()
                maxZoomRatio = cam.cameraInfo.zoomState.value?.maxZoomRatio?.coerceIn(1f, 6f) ?: 4f

                // Initial center AF + AE lock to resolve small or screen-displayed QR codes quickly
                val centerFactory = SurfaceOrientedMeteringPointFactory(1f, 1f)
                val centerPoint = centerFactory.createPoint(0.5f, 0.5f)
                val initFocus = FocusMeteringAction.Builder(
                    centerPoint,
                    FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE
                ).setAutoCancelDuration(3, TimeUnit.SECONDS).build()
                runCatching { cam.cameraControl.startFocusAndMetering(initFocus) }
            }.onFailure { err ->
                onCameraUnavailable("Camera preview unavailable (${err.message ?: "unknown error"}). Use Import QR Image or Session Code pairing.")
            }
        }
        future.addListener(listener, mainExec)

        onDispose {
            runCatching { future.get().unbindAll() }
            boundCamera = null
            analysisExecutor.shutdownNow()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .clip(RoundedCornerShape(8.dp))
            .pointerInput(boundCamera) {
                detectTapGestures { offset ->
                    val cam = boundCamera ?: return@detectTapGestures
                    focusReticle = offset
                    val factory = previewView.meteringPointFactory
                    val point = factory.createPoint(offset.x, offset.y)
                    val action = FocusMeteringAction.Builder(
                        point,
                        FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE
                    ).setAutoCancelDuration(3, TimeUnit.SECONDS).build()
                    runCatching { cam.cameraControl.startFocusAndMetering(action) }
                }
            }
            .pointerInput(boundCamera, maxZoomRatio) {
                detectTransformGestures { _, _, zoom, _ ->
                    val cam = boundCamera ?: return@detectTransformGestures
                    if (zoom != 1f) {
                        val next = (currentZoomRatio * zoom).coerceIn(1.0f, maxZoomRatio)
                        currentZoomRatio = next
                        runCatching { cam.cameraControl.setZoomRatio(next) }
                    }
                }
            }
    ) {
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize()
        )

        val reticle = focusReticle
        AnimatedVisibility(
            visible = reticle != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.fillMaxSize()
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val center = reticle ?: return@Canvas
                drawCircle(
                    color = Color(0xFF00E5FF),
                    radius = 28.dp.toPx(),
                    center = center,
                    style = Stroke(width = 2.5.dp.toPx())
                )
            }
        }

        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(8.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val target2x = minOf(2.0f, maxZoomRatio)
            if (target2x > 1.2f) {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = Color.Black.copy(alpha = 0.65f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.3f)),
                    onClick = {
                        val cam = boundCamera ?: return@Surface
                        val nextZoom = if (currentZoomRatio > 1.3f) 1.0f else target2x
                        currentZoomRatio = nextZoom
                        runCatching { cam.cameraControl.setZoomRatio(nextZoom) }
                    }
                ) {
                    Text(
                        text = if (currentZoomRatio > 1.3f) "2x" else "1x",
                        color = Color.White,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp)
                    )
                }
            }

            if (hasFlash) {
                Surface(
                    shape = RoundedCornerShape(16.dp),
                    color = Color.Black.copy(alpha = 0.65f),
                    border = BorderStroke(1.dp, Color.White.copy(alpha = 0.3f))
                ) {
                    IconButton(
                        onClick = {
                            val cam = boundCamera ?: return@IconButton
                            val nextTorch = !torchEnabled
                            torchEnabled = nextTorch
                            runCatching { cam.cameraControl.enableTorch(nextTorch) }
                        },
                        modifier = Modifier.size(34.dp)
                    ) {
                        Icon(
                            imageVector = if (torchEnabled) Icons.Default.FlashOn else Icons.Default.FlashOff,
                            contentDescription = if (torchEnabled) "Disable Torch" else "Enable Torch",
                            tint = if (torchEnabled) Color(0xFFFACC15) else Color.White,
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            }
        }
    }
}
