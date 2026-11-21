package com.saabithjiffry.presentersync.remote.ui.screens

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.PowerManager
import android.provider.Settings
import android.widget.Toast
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.material3.AlertDialog
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import com.saabithjiffry.presentersync.remote.config.PairingUriBuilder
import com.saabithjiffry.presentersync.remote.network.DualEndpointProbe
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.RelayCrypto
import com.saabithjiffry.presentersync.remote.ui.theme.CompactExplorerButtonPadding
import com.saabithjiffry.presentersync.remote.ui.theme.ExplorerCard
import kotlinx.coroutines.launch

@Composable
fun ConnectionSettingsDialog(
    initialConfig: RemoteConfig,
    configStore: RemoteConfigStore,
    connectionManager: ConnectionManager,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val formFactor = rememberFormFactor(initialConfig.deviceProfileMode)
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = formFactor.dialogMaxWidthDp)
                .fillMaxWidth(formFactor.dialogWidthFraction)
                .heightIn(max = (formFactor.heightDp * formFactor.dialogMaxHeightFraction).dp)
                .padding(vertical = if (formFactor.isCompactHeight) 6.dp else 14.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
            tonalElevation = 0.dp
        ) {
            ConnectionSettingsForm(
                initialConfig = initialConfig,
                configStore = configStore,
                connectionManager = connectionManager,
                formFactor = formFactor,
                onDismiss = onDismiss,
                onSaved = onSaved
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ConnectionSettingsForm(
    initialConfig: RemoteConfig,
    configStore: RemoteConfigStore,
    connectionManager: ConnectionManager,
    formFactor: ResolvedFormFactor = rememberFormFactor(initialConfig.deviceProfileMode),
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val scope = rememberCoroutineScope()

    var networkMode by remember(initialConfig) { mutableStateOf(initialConfig.networkMode) }
    var sessionCodeInput by remember(initialConfig) { mutableStateOf(initialConfig.sessionPairingCode) }
    var pairingCode by remember(initialConfig) { mutableStateOf(initialConfig.internetPairingCode) }
    var relayBaseUrl by remember(initialConfig) { mutableStateOf(initialConfig.relayBaseUrl) }
    var hostAddress by remember(initialConfig) { mutableStateOf(initialConfig.hostAddress) }
    var hostPortStr by remember(initialConfig) { mutableStateOf(initialConfig.hostPort.toString()) }
    var bridgePortStr by remember(initialConfig) { mutableStateOf(initialConfig.bridgePort.toString()) }
    var obsPassword by remember(initialConfig) { mutableStateOf(initialConfig.obsPassword) }
    var showPassword by remember { mutableStateOf(false) }
    var targetMicName by remember(initialConfig) { mutableStateOf(initialConfig.targetMicName) }
    var heartbeatStr by remember(initialConfig) { mutableStateOf(initialConfig.heartbeatSeconds.toString()) }
    var enableRelayFallback by remember(initialConfig) { mutableStateOf(initialConfig.enableRelayFallback) }
    var savedProfiles by remember(initialConfig) { mutableStateOf(initialConfig.savedProfiles) }
    var selectedProfileId by remember(initialConfig) { mutableStateOf(initialConfig.activeProfileId) }
    var profileNameInput by remember(initialConfig) {
        mutableStateOf(
            initialConfig.savedProfiles.firstOrNull { it.id == initialConfig.activeProfileId }?.name.orEmpty()
        )
    }

    var testing by remember { mutableStateOf(false) }
    var pairing by remember { mutableStateOf(false) }
    var scanningLan by remember { mutableStateOf(false) }
    var discoveredHosts by remember {
        mutableStateOf<List<com.saabithjiffry.presentersync.remote.network.DiscoveredPublicHost>>(emptyList())
    }
    var selectedHostUuid by remember(initialConfig) { mutableStateOf(initialConfig.pairedHostUuid) }
    var showQrScanner by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf("") }
    var validationError by remember { mutableStateOf<String?>(null) }

    Column(modifier = Modifier.fillMaxWidth()) {
        // Pinned Fluent dialog header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "OBS Remote Connection",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "Configure LAN WebSocket or WAN Internet Relay",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(onClick = onDismiss) {
                Icon(Icons.Default.Close, contentDescription = "Close")
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        // Scrollable form fields
        Column(
            modifier = Modifier
                .weight(1f, fill = false)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Easy QR / Session Code Pairing (Camera or No-Camera Smart Board Flow)
            ExplorerCard(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                borderColor = MaterialTheme.colorScheme.outline,
                contentPadding = 14
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Quick Pair (QR or Session Code)",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedButton(
                            onClick = {
                                if (scanningLan || pairing || testing) return@OutlinedButton
                                scanningLan = true
                                statusText = "Scanning classroom LAN (:4457)..."
                                scope.launch {
                                    val found = connectionManager.scanClassroomHosts()
                                    discoveredHosts = found
                                    scanningLan = false
                                    statusText = if (found.isEmpty()) {
                                        "No classroom hosts responded on UDP :4457."
                                    } else {
                                        "Found ${found.size} classroom host(s). Tap one to fill details."
                                    }
                                }
                            },
                            enabled = !scanningLan && !pairing && !testing,
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            if (scanningLan) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                                Spacer(Modifier.width(5.dp))
                            }
                            Text(if (formFactor.isTightWidth) "Scan LAN" else "Scan Classroom", maxLines = 1, softWrap = false)
                        }
                        OutlinedButton(
                            onClick = { showQrScanner = true },
                            enabled = !pairing && !testing,
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            Icon(
                                Icons.Default.QrCodeScanner,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text("Scan QR", maxLines = 1, softWrap = false)
                        }
                    }
                    if (discoveredHosts.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            discoveredHosts.forEach { host ->
                                OutlinedButton(
                                    onClick = {
                                        hostAddress = host.hostIp
                                        bridgePortStr = host.bridgePort.toString()
                                        hostPortStr = host.obsPort.toString()
                                        selectedHostUuid = host.hostUuid
                                        networkMode = NetworkMode.LAN
                                        statusText = "Selected ${host.displayTitle} (${host.hostIp})."
                                        val codeNow = sessionCodeInput.trim()
                                        if (codeNow.isNotEmpty() && !pairing) {
                                            pairing = true
                                            statusText = "Pairing with ${host.deviceName}..."
                                            scope.launch {
                                                val msg = connectionManager.pairByCode(
                                                    codeInput = codeNow,
                                                    fallbackHostInput = host.hostIp,
                                                    bridgePortInput = host.bridgePort,
                                                    onProgress = { statusText = it }
                                                )
                                                val updated = configStore.current
                                                networkMode = updated.networkMode
                                                sessionCodeInput = updated.sessionPairingCode
                                                pairingCode = updated.internetPairingCode
                                                hostAddress = updated.hostAddress
                                                hostPortStr = updated.hostPort.toString()
                                                bridgePortStr = updated.bridgePort.toString()
                                                obsPassword = updated.obsPassword
                                                targetMicName = updated.targetMicName
                                                selectedHostUuid = updated.pairedHostUuid
                                                statusText = msg
                                                pairing = false
                                            }
                                        }
                                    },
                                    contentPadding = CompactExplorerButtonPadding,
                                    modifier = Modifier.fillMaxWidth()
                                ) {
                                    Text(
                                        "${host.displayTitle} (${host.hostIp})",
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                    Text(
                        text = "Scan the QR code from PresenterSync > Remote Setup, or type the 6-char Host Session Code (e.g. K7M-9P2) or Internet Code (PS-...).",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (formFactor.isTightWidth) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedTextField(
                                value = sessionCodeInput,
                                onValueChange = { sessionCodeInput = it.uppercase() },
                                label = { Text("Session / Relay Code") },
                                placeholder = { Text("K7M-9P2") },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth()
                            )
                            Button(
                                onClick = {
                                    if (pairing || testing) return@Button
                                    validationError = null
                                    pairing = true
                                    statusText = "Pairing with Primary Host..."
                                    val bPort = bridgePortStr.trim().toIntOrNull()?.takeIf { it in 1..65535 }
                                        ?: AppConstants.DEFAULT_BRIDGE_PORT
                                    scope.launch {
                                        val msg = connectionManager.pairByCode(
                                            codeInput = sessionCodeInput,
                                            fallbackHostInput = hostAddress,
                                            bridgePortInput = bPort,
                                            onProgress = { statusText = it }
                                        )
                                        val updated = configStore.current
                                        networkMode = updated.networkMode
                                        sessionCodeInput = updated.sessionPairingCode
                                        pairingCode = updated.internetPairingCode
                                        hostAddress = updated.hostAddress
                                        hostPortStr = updated.hostPort.toString()
                                        bridgePortStr = updated.bridgePort.toString()
                                        obsPassword = updated.obsPassword
                                        targetMicName = updated.targetMicName
                                        statusText = msg
                                        pairing = false
                                    }
                                },
                                enabled = !pairing && !testing,
                                contentPadding = CompactExplorerButtonPadding,
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                if (pairing) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary
                                    )
                                    Spacer(Modifier.width(6.dp))
                                }
                                Text("Discover & Pair", maxLines = 1, softWrap = false)
                            }
                        }
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            OutlinedTextField(
                                value = sessionCodeInput,
                                onValueChange = { sessionCodeInput = it.uppercase() },
                                label = { Text("Session / Relay Code") },
                                placeholder = { Text("K7M-9P2") },
                                singleLine = true,
                                modifier = Modifier.weight(1f)
                            )
                            Button(
                                onClick = {
                                    if (pairing || testing) return@Button
                                    validationError = null
                                    pairing = true
                                    statusText = "Pairing with Primary Host..."
                                    val bPort = bridgePortStr.trim().toIntOrNull()?.takeIf { it in 1..65535 }
                                        ?: AppConstants.DEFAULT_BRIDGE_PORT
                                    scope.launch {
                                        val msg = connectionManager.pairByCode(
                                            codeInput = sessionCodeInput,
                                            fallbackHostInput = hostAddress,
                                            bridgePortInput = bPort,
                                            onProgress = { statusText = it }
                                        )
                                        val updated = configStore.current
                                        networkMode = updated.networkMode
                                        sessionCodeInput = updated.sessionPairingCode
                                        pairingCode = updated.internetPairingCode
                                        hostAddress = updated.hostAddress
                                        hostPortStr = updated.hostPort.toString()
                                        bridgePortStr = updated.bridgePort.toString()
                                        obsPassword = updated.obsPassword
                                        targetMicName = updated.targetMicName
                                        statusText = msg
                                        pairing = false
                                    }
                                },
                                enabled = !pairing && !testing,
                                contentPadding = CompactExplorerButtonPadding
                            ) {
                                if (pairing) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(16.dp),
                                        strokeWidth = 2.dp,
                                        color = MaterialTheme.colorScheme.onPrimary
                                    )
                                    Spacer(Modifier.width(6.dp))
                                }
                                Text("Discover & Pair", maxLines = 1, softWrap = false)
                            }
                        }
                    }
                }
            }

            // Saved Room / Host Profiles Switcher
            ExplorerCard(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
                borderColor = MaterialTheme.colorScheme.outline,
                contentPadding = 14
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "Saved Rooms & Host Profiles",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (savedProfiles.isNotEmpty()) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            savedProfiles.forEach { prof ->
                                FilterChip(
                                    selected = selectedProfileId == prof.id,
                                    onClick = {
                                        selectedProfileId = prof.id
                                        profileNameInput = prof.name
                                        networkMode = prof.networkMode
                                        hostAddress = prof.hostAddress
                                        hostPortStr = prof.hostPort.toString()
                                        bridgePortStr = prof.bridgePort.toString()
                                        obsPassword = prof.obsPassword
                                        pairingCode = prof.internetPairingCode
                                        relayBaseUrl = prof.relayBaseUrl
                                        sessionCodeInput = prof.sessionPairingCode
                                        targetMicName = prof.targetMicName
                                        heartbeatStr = prof.heartbeatSeconds.toString()
                                        configStore.switchToProfile(prof.id)
                                        statusText = "Loaded room profile '${prof.name}'"
                                    },
                                    label = { Text(prof.name, maxLines = 1, softWrap = false) }
                                )
                            }
                        }
                    } else {
                        Text(
                            text = "Save room IPs & codes once, then switch halls in one tap.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        OutlinedTextField(
                            value = profileNameInput,
                            onValueChange = { profileNameInput = it },
                            label = { Text("Room / Host Name") },
                            placeholder = { Text("e.g. Lecture Hall 201") },
                            singleLine = true,
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedButton(
                            onClick = {
                                val hPort = hostPortStr.trim().toIntOrNull()?.takeIf { it in 1..65535 } ?: AppConstants.DEFAULT_OBS_PORT
                                val bPort = bridgePortStr.trim().toIntOrNull()?.takeIf { it in 1..65535 } ?: AppConstants.DEFAULT_BRIDGE_PORT
                                val hb = heartbeatStr.trim().toIntOrNull()?.takeIf { it in 10..3600 } ?: AppConstants.DEFAULT_HEARTBEAT_SECONDS
                                val cleanMic = targetMicName.trim().ifEmpty { AppConstants.DEFAULT_MIC_NAME }
                                configStore.update { prev ->
                                    prev.copy(
                                        networkMode = networkMode,
                                        sessionPairingCode = sessionCodeInput.trim(),
                                        internetPairingCode = pairingCode.trim(),
                                        relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(relayBaseUrl),
                                        hostAddress = hostAddress.trim(),
                                        hostPort = hPort,
                                        bridgePort = bPort,
                                        obsPassword = obsPassword,
                                        targetMicName = cleanMic,
                                        heartbeatSeconds = hb
                                    )
                                }
                                val saved = configStore.saveCurrentAsProfile(profileNameInput)
                                savedProfiles = configStore.current.savedProfiles
                                selectedProfileId = saved.id
                                profileNameInput = saved.name
                                statusText = "✓ Saved room '${saved.name}'"
                            },
                            contentPadding = CompactExplorerButtonPadding
                        ) {
                            Text("Save Room", maxLines = 1, softWrap = false)
                        }
                        if (selectedProfileId.isNotEmpty() && savedProfiles.any { it.id == selectedProfileId }) {
                            IconButton(
                                onClick = {
                                    configStore.deleteSavedProfile(selectedProfileId)
                                    savedProfiles = configStore.current.savedProfiles
                                    selectedProfileId = ""
                                    profileNameInput = ""
                                    statusText = "Deleted saved room profile."
                                }
                            ) {
                                Icon(Icons.Default.Close, contentDescription = "Delete room profile")
                            }
                        }
                    }
                }
            }

            // Network mode chips
            Text(
                text = "Manual Network & Host Settings",
                style = MaterialTheme.typography.labelLarge
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                FilterChip(
                    selected = networkMode == NetworkMode.LAN,
                    onClick = { networkMode = NetworkMode.LAN },
                    label = { Text("LAN (Bridge / Direct OBS)") }
                )
                FilterChip(
                    selected = networkMode == NetworkMode.INTERNET,
                    onClick = { networkMode = NetworkMode.INTERNET },
                    label = { Text("Internet (Relay)") }
                )
            }

            OutlinedTextField(
                value = pairingCode,
                onValueChange = { pairingCode = it },
                label = {
                    Text(
                        if (networkMode == NetworkMode.INTERNET) {
                            "Internet Pairing Code (Required)"
                        } else {
                            "Internet Pairing Code (Optional / Fallback)"
                        }
                    )
                },
                placeholder = { Text("e.g. PS-A1B2-C3D4") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = relayBaseUrl,
                onValueChange = { relayBaseUrl = it },
                label = { Text("Relay Server URL (ntfy)") },
                placeholder = { Text(AppConstants.NTFY_BASE_URL) },
                supportingText = {
                    Text("Default: https://ntfy.sh (supports self-hosted http:// or https://). Payloads are AES-256-GCM encrypted.")
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedTextField(
                value = hostAddress,
                onValueChange = { hostAddress = it },
                label = { Text("OBS Host IP / Hostname Candidates") },
                placeholder = { Text("e.g. 192.168.1.50, pc.local") },
                supportingText = {
                    Text("Comma or semicolon separated for automatic failover.")
                },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                OutlinedTextField(
                    value = hostPortStr,
                    onValueChange = { hostPortStr = it.filter { ch -> ch.isDigit() } },
                    label = { Text("OBS Port") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                OutlinedTextField(
                    value = bridgePortStr,
                    onValueChange = { bridgePortStr = it.filter { ch -> ch.isDigit() } },
                    label = { Text("Bridge Port") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                OutlinedTextField(
                    value = heartbeatStr,
                    onValueChange = { heartbeatStr = it.filter { ch -> ch.isDigit() } },
                    label = { Text("Heartbeat (s)") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
            }

        OutlinedTextField(
            value = obsPassword,
            onValueChange = { obsPassword = it },
            label = { Text("OBS WebSocket Password") },
            singleLine = true,
            visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(onClick = { showPassword = !showPassword }) {
                    Icon(
                        imageVector = if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                        contentDescription = if (showPassword) "Hide password" else "Show password"
                    )
                }
            },
            modifier = Modifier.fillMaxWidth()
        )

        OutlinedTextField(
            value = targetMicName,
            onValueChange = { targetMicName = it },
            label = { Text("Target Mic Source Name in OBS") },
            placeholder = { Text(AppConstants.DEFAULT_MIC_NAME) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f).padding(end = 12.dp)) {
                Text("Auto Relay Fallback", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
                Text(
                    "Fall back to WAN Relay automatically if all LAN endpoints fail",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Switch(
                checked = enableRelayFallback,
                onCheckedChange = { enableRelayFallback = it }
            )
        }
        } // end scrollable form column

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        // Pinned action footer
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
        if (!validationError.isNullOrEmpty()) {
            Text(
                text = validationError!!,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium
            )
        }

        val context = androidx.compose.ui.platform.LocalContext.current
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val ignoringBattery = pm?.isIgnoringBatteryOptimizations(context.packageName) ?: true
        if (!ignoringBattery) {
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFD97706).copy(alpha = 0.14f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(
                    modifier = Modifier.padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "Battery optimization is enabled — Android may throttle background WebSocket & BT clicker.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFFD97706),
                        fontWeight = FontWeight.Medium
                    )
                    OutlinedButton(
                        onClick = {
                            runCatching {
                                context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            }
                        },
                        contentPadding = CompactExplorerButtonPadding
                    ) {
                        Text("Disable Battery Optimization", maxLines = 1, softWrap = false)
                    }
                }
            }
        }

        var showShareQrDialog by remember { mutableStateOf(false) }
        val clipboard = LocalClipboardManager.current
        OutlinedButton(
            onClick = { showShareQrDialog = true },
            contentPadding = CompactExplorerButtonPadding,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Share Pairing QR", maxLines = 1, softWrap = false)
        }
        if (showShareQrDialog) {
            val shareUri = remember(hostAddress, bridgePortStr, pairingCode, hostPortStr, obsPassword) {
                PairingUriBuilder.build(
                    initialConfig.copy(
                        hostAddress = hostAddress,
                        bridgePort = bridgePortStr.toIntOrNull() ?: 4456,
                        sessionPairingCode = pairingCode,
                        hostPort = hostPortStr.toIntOrNull() ?: 4455,
                        obsPassword = obsPassword
                    )
                )
            }
            val qrBitmap = remember(shareUri) {
                runCatching {
                    val matrix = QRCodeWriter().encode(shareUri, BarcodeFormat.QR_CODE, 420, 420)
                    Bitmap.createBitmap(420, 420, Bitmap.Config.ARGB_8888).apply {
                        for (x in 0 until 420) {
                            for (y in 0 until 420) {
                                setPixel(x, y, if (matrix.get(x, y)) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
                            }
                        }
                    }
                }.getOrNull()
            }
            AlertDialog(
                onDismissRequest = { showShareQrDialog = false },
                title = { Text("Share Pairing QR") },
                text = {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        if (qrBitmap != null) {
                            Image(
                                bitmap = qrBitmap.asImageBitmap(),
                                contentDescription = "Pairing QR Code",
                                modifier = Modifier.size(220.dp)
                            )
                        }
                        Text(
                            text = shareUri,
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                },
                confirmButton = {
                    Button(onClick = {
                        clipboard.setText(AnnotatedString(shareUri))
                        Toast.makeText(context, "Pairing URI copied", Toast.LENGTH_SHORT).show()
                    }) {
                        Text("Copy URI")
                    }
                },
                dismissButton = {
                    OutlinedButton(onClick = { showShareQrDialog = false }) {
                        Text("Close")
                    }
                }
            )
        }

        if (statusText.isNotEmpty()) {
            val statusColor = when {
                statusText.startsWith("✓") -> Color(0xFF10B981)
                statusText.startsWith("✕") || statusText.startsWith("Error:") -> MaterialTheme.colorScheme.error
                else -> MaterialTheme.colorScheme.primary
            }
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant
                ),
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(
                    text = statusText,
                    color = statusColor,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.padding(12.dp)
                )
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            OutlinedButton(
                onClick = {
                    if (testing) return@OutlinedButton
                    validationError = null
                    testing = true
                    statusText = "Testing..."
                    scope.launch {
                        val dualSummary = if (networkMode == NetworkMode.LAN) {
                            val firstHost = hostAddress.split(",").firstOrNull()?.trim().orEmpty()
                            DualEndpointProbe.probe(
                                host = firstHost,
                                bridgePort = bridgePortStr.toIntOrNull() ?: 4456,
                                obsPort = hostPortStr.toIntOrNull() ?: 4455
                            ).formatSummary()
                        } else ""
                        val res = connectionManager.testConnection(
                            networkMode = networkMode,
                            hostAddress = hostAddress,
                            portStr = hostPortStr,
                            password = obsPassword,
                            pairingCode = pairingCode,
                            onProgress = { msg -> statusText = msg },
                            relayBaseUrl = relayBaseUrl
                        )
                        statusText = if (dualSummary.isNotEmpty()) "$res\n$dualSummary" else res
                        testing = false
                    }
                },
                enabled = !testing,
                contentPadding = CompactExplorerButtonPadding,
                modifier = Modifier.weight(1f)
            ) {
                if (testing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(6.dp))
                }
                Text(
                    if (formFactor.isTightWidth) "Test" else "Test Connection",
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Button(
                onClick = {
                    val port = hostPortStr.trim().toIntOrNull()
                    if (port == null || port !in 1..65535) {
                        validationError = "OBS Port must be between 1 and 65535."
                        return@Button
                    }
                    val bPort = bridgePortStr.trim().toIntOrNull()
                    if (bPort == null || bPort !in 1..65535) {
                        validationError = "Bridge Port must be between 1 and 65535."
                        return@Button
                    }
                    val hb = heartbeatStr.trim().toIntOrNull()
                    if (hb == null || hb !in 10..3600) {
                        validationError = "Heartbeat interval must be between 10 and 3600 seconds."
                        return@Button
                    }
                    if (networkMode == NetworkMode.INTERNET && pairingCode.trim().isEmpty()) {
                        validationError = "Internet Pairing Code is required in Internet mode."
                        return@Button
                    }
                    if (networkMode == NetworkMode.LAN && hostAddress.trim().isEmpty()) {
                        validationError = "Enter at least one OBS Host IP or hostname."
                        return@Button
                    }

                    validationError = null
                    val cleanMic = targetMicName.trim().ifEmpty { AppConstants.DEFAULT_MIC_NAME }
                    configStore.update { prev ->
                        prev.copy(
                            networkMode = networkMode,
                            sessionPairingCode = sessionCodeInput.trim(),
                            pairedHostUuid = selectedHostUuid.ifBlank { prev.pairedHostUuid },
                            internetPairingCode = pairingCode.trim(),
                            relayBaseUrl = RelayCrypto.normalizeRelayBaseUrl(relayBaseUrl),
                            hostAddress = hostAddress.trim(),
                            hostPort = port,
                            bridgePort = bPort,
                            obsPassword = obsPassword,
                            targetMicName = cleanMic,
                            heartbeatSeconds = hb,
                            enableRelayFallback = enableRelayFallback,
                            firstRun = false
                        )
                    }
                    connectionManager.reconnectNow()
                    onSaved()
                },
                contentPadding = CompactExplorerButtonPadding,
                modifier = Modifier.weight(1f)
            ) {
                Text(
                    if (formFactor.isTightWidth) "Save" else "Save & Reconnect",
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        } // end pinned footer column
    }

    if (showQrScanner) {
        QrScannerDialog(
            onPayloadScanned = { payload ->
                showQrScanner = false
                validationError = null
                networkMode = payload.networkMode
                if (payload.hostsCsv.isNotBlank()) hostAddress = payload.hostsCsv
                hostPortStr = payload.obsPort.toString()
                bridgePortStr = payload.bridgePort.toString()
                if (payload.obsPassword.isNotEmpty()) obsPassword = payload.obsPassword
                if (payload.targetMicName.isNotBlank()) targetMicName = payload.targetMicName
                if (payload.sessionCode.isNotBlank()) sessionCodeInput = payload.sessionCode
                if (payload.internetPairingCode.isNotBlank()) pairingCode = payload.internetPairingCode

                pairing = true
                statusText = "Applying QR connection profile..."
                scope.launch {
                    val msg = connectionManager.applyDeepLinkPayload(
                        payload = payload,
                        onProgress = { statusText = it }
                    )
                    val updated = configStore.current
                    networkMode = updated.networkMode
                    sessionCodeInput = updated.sessionPairingCode
                    pairingCode = updated.internetPairingCode
                    hostAddress = updated.hostAddress
                    hostPortStr = updated.hostPort.toString()
                    bridgePortStr = updated.bridgePort.toString()
                    obsPassword = updated.obsPassword
                    targetMicName = updated.targetMicName
                    selectedHostUuid = updated.pairedHostUuid
                    statusText = msg
                    pairing = false
                }
            },
            onDismiss = { showQrScanner = false }
        )
    }
}
