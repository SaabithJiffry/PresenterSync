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
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.config.ResolvedFormFactor
import com.saabithjiffry.presentersync.remote.config.SavedHostProfile
import com.saabithjiffry.presentersync.remote.config.rememberFormFactor
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import com.saabithjiffry.presentersync.remote.network.DiscoveredPublicHost
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
        properties = DialogProperties(usePlatformDefaultWidth = false, securePolicy = SecureFlagPolicy.SecureOn)
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
    var currentKioskPin by remember(initialConfig) { mutableStateOf(initialConfig.kioskPin) }
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
    var discoveredHosts by remember { mutableStateOf<List<DiscoveredPublicHost>>(emptyList()) }
    var selectedHostUuid by remember(initialConfig) { mutableStateOf(initialConfig.pairedHostUuid) }
    var showQrScanner by remember { mutableStateOf(false) }
    var statusText by remember { mutableStateOf("") }
    var validationError by remember { mutableStateOf<String?>(null) }

    fun syncFormFromConfig(updated: RemoteConfig, syncHostUuid: Boolean = true) {
        networkMode = updated.networkMode
        sessionCodeInput = updated.sessionPairingCode
        pairingCode = updated.internetPairingCode
        hostAddress = updated.hostAddress
        hostPortStr = updated.hostPort.toString()
        bridgePortStr = updated.bridgePort.toString()
        obsPassword = updated.obsPassword
        targetMicName = updated.targetMicName
        if (syncHostUuid) {
            selectedHostUuid = updated.pairedHostUuid
        }
    }

    fun launchCodePairing(code: String, fallbackHost: String, bridgePort: Int, initialMessage: String) {
        if (pairing || testing) return
        validationError = null
        pairing = true
        statusText = initialMessage
        scope.launch {
            val msg = connectionManager.pairByCode(
                codeInput = code,
                fallbackHostInput = fallbackHost,
                bridgePortInput = bridgePort,
                onProgress = { statusText = it }
            )
            syncFormFromConfig(configStore.current)
            statusText = msg
            pairing = false
        }
    }

    fun validateAndSave() {
        val port = hostPortStr.trim().toIntOrNull()
        if (port == null || port !in 1..65535) {
            validationError = "OBS Port must be between 1 and 65535."
            return
        }
        val bPort = bridgePortStr.trim().toIntOrNull()
        if (bPort == null || bPort !in 1..65535) {
            validationError = "Bridge Port must be between 1 and 65535."
            return
        }
        val hb = heartbeatStr.trim().toIntOrNull()
        if (hb == null || hb !in 10..3600) {
            validationError = "Heartbeat interval must be between 10 and 3600 seconds."
            return
        }
        if (networkMode == NetworkMode.INTERNET && pairingCode.trim().isEmpty()) {
            validationError = "Internet Pairing Code is required in Internet mode."
            return
        }
        if (networkMode == NetworkMode.LAN && hostAddress.trim().isEmpty()) {
            validationError = "Enter at least one OBS Host IP or hostname."
            return
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
    }

    Column(modifier = Modifier.fillMaxWidth()) {
        ConnectionDialogHeader(onDismiss = onDismiss)
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
            QuickPairCard(
                formFactor = formFactor,
                sessionCodeInput = sessionCodeInput,
                onSessionCodeChange = { sessionCodeInput = it.uppercase() },
                discoveredHosts = discoveredHosts,
                scanningLan = scanningLan,
                pairing = pairing,
                testing = testing,
                onScanLan = {
                    if (scanningLan || pairing || testing) return@QuickPairCard
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
                onOpenQrScanner = { showQrScanner = true },
                onSelectDiscoveredHost = { host ->
                    hostAddress = host.hostIp
                    bridgePortStr = host.bridgePort.toString()
                    hostPortStr = host.obsPort.toString()
                    selectedHostUuid = host.hostUuid
                    networkMode = NetworkMode.LAN
                    statusText = "Selected ${host.displayTitle} (${host.hostIp})."
                    val codeNow = sessionCodeInput.trim()
                    if (codeNow.isNotEmpty() && !pairing) {
                        launchCodePairing(
                            code = codeNow,
                            fallbackHost = host.hostIp,
                            bridgePort = host.bridgePort,
                            initialMessage = "Pairing with ${host.deviceName}..."
                        )
                    }
                },
                onDiscoverAndPair = {
                    val bPort = bridgePortStr.trim().toIntOrNull()?.takeIf { it in 1..65535 }
                        ?: AppConstants.DEFAULT_BRIDGE_PORT
                    launchCodePairing(
                        code = sessionCodeInput,
                        fallbackHost = hostAddress,
                        bridgePort = bPort,
                        initialMessage = "Pairing with Primary Host..."
                    )
                }
            )

            SavedRoomProfilesCard(
                savedProfiles = savedProfiles,
                selectedProfileId = selectedProfileId,
                profileNameInput = profileNameInput,
                onProfileNameChange = { profileNameInput = it },
                onSelectProfile = { prof ->
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
                onSaveRoomProfile = {
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
                onDeleteSelectedProfile = {
                    configStore.deleteSavedProfile(selectedProfileId)
                    savedProfiles = configStore.current.savedProfiles
                    selectedProfileId = ""
                    profileNameInput = ""
                    statusText = "Deleted saved room profile."
                }
            )

            ManualNetworkSettingsSection(
                networkMode = networkMode,
                onNetworkModeChange = { networkMode = it },
                pairingCode = pairingCode,
                onPairingCodeChange = { pairingCode = it },
                relayBaseUrl = relayBaseUrl,
                onRelayBaseUrlChange = { relayBaseUrl = it },
                hostAddress = hostAddress,
                onHostAddressChange = { hostAddress = it },
                hostPortStr = hostPortStr,
                onHostPortChange = { hostPortStr = it.filter(Char::isDigit) },
                bridgePortStr = bridgePortStr,
                onBridgePortChange = { bridgePortStr = it.filter(Char::isDigit) },
                heartbeatStr = heartbeatStr,
                onHeartbeatChange = { heartbeatStr = it.filter(Char::isDigit) },
                obsPassword = obsPassword,
                onObsPasswordChange = { obsPassword = it },
                showPassword = showPassword,
                onToggleShowPassword = { showPassword = !showPassword },
                targetMicName = targetMicName,
                onTargetMicNameChange = { targetMicName = it },
                enableRelayFallback = enableRelayFallback,
                onToggleRelayFallback = { enableRelayFallback = it }
            )

            KioskPinManagementCard(
                currentPin = currentKioskPin,
                onUpdatePin = { newPin ->
                    val cleanPin = newPin.trim()
                    currentKioskPin = cleanPin
                    configStore.update { it.copy(kioskPin = cleanPin) }
                    statusText = if (cleanPin.isBlank()) "✓ Kiosk PIN cleared." else "✓ Kiosk PIN updated."
                }
            )
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        ConnectionDialogActionFooter(
            initialConfig = initialConfig,
            formFactor = formFactor,
            networkMode = networkMode,
            hostAddress = hostAddress,
            bridgePortStr = bridgePortStr,
            sessionCodeInput = sessionCodeInput,
            pairingCode = pairingCode,
            relayBaseUrl = relayBaseUrl,
            hostPortStr = hostPortStr,
            validationError = validationError,
            statusText = statusText,
            testing = testing,
            onTestConnection = {
                if (testing) return@ConnectionDialogActionFooter
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
            onSaveAndReconnect = { validateAndSave() }
        )
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
                    syncFormFromConfig(configStore.current)
                    statusText = msg
                    pairing = false
                }
            },
            onDismiss = { showQrScanner = false }
        )
    }
}

@Composable
private fun ConnectionDialogHeader(onDismiss: () -> Unit) {
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
}

@Composable
private fun QuickPairCard(
    formFactor: ResolvedFormFactor,
    sessionCodeInput: String,
    onSessionCodeChange: (String) -> Unit,
    discoveredHosts: List<DiscoveredPublicHost>,
    scanningLan: Boolean,
    pairing: Boolean,
    testing: Boolean,
    onScanLan: () -> Unit,
    onOpenQrScanner: () -> Unit,
    onSelectDiscoveredHost: (DiscoveredPublicHost) -> Unit,
    onDiscoverAndPair: () -> Unit
) {
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
                    onClick = onScanLan,
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
                    onClick = onOpenQrScanner,
                    enabled = !pairing && !testing,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Icon(Icons.Default.QrCodeScanner, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Scan QR", maxLines = 1, softWrap = false)
                }
            }
            if (discoveredHosts.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    discoveredHosts.forEach { host ->
                        OutlinedButton(
                            onClick = { onSelectDiscoveredHost(host) },
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
                    SessionCodeInputField(sessionCodeInput, onSessionCodeChange, Modifier.fillMaxWidth())
                    DiscoverAndPairButton(pairing, testing, onDiscoverAndPair, Modifier.fillMaxWidth())
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    SessionCodeInputField(sessionCodeInput, onSessionCodeChange, Modifier.weight(1f))
                    DiscoverAndPairButton(pairing, testing, onDiscoverAndPair, Modifier)
                }
            }
        }
    }
}

@Composable
private fun SessionCodeInputField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text("Session / Relay Code") },
        placeholder = { Text("K7M-9P2") },
        singleLine = true,
        modifier = modifier
    )
}

@Composable
private fun DiscoverAndPairButton(
    pairing: Boolean,
    testing: Boolean,
    onClick: () -> Unit,
    modifier: Modifier
) {
    Button(
        onClick = onClick,
        enabled = !pairing && !testing,
        contentPadding = CompactExplorerButtonPadding,
        modifier = modifier
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

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SavedRoomProfilesCard(
    savedProfiles: List<SavedHostProfile>,
    selectedProfileId: String,
    profileNameInput: String,
    onProfileNameChange: (String) -> Unit,
    onSelectProfile: (SavedHostProfile) -> Unit,
    onSaveRoomProfile: () -> Unit,
    onDeleteSelectedProfile: () -> Unit
) {
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
                            onClick = { onSelectProfile(prof) },
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
                    onValueChange = onProfileNameChange,
                    label = { Text("Room / Host Name") },
                    placeholder = { Text("e.g. Lecture Hall 201") },
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
                OutlinedButton(
                    onClick = onSaveRoomProfile,
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text("Save Room", maxLines = 1, softWrap = false)
                }
                if (selectedProfileId.isNotEmpty() && savedProfiles.any { it.id == selectedProfileId }) {
                    IconButton(onClick = onDeleteSelectedProfile) {
                        Icon(Icons.Default.Close, contentDescription = "Delete room profile")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ManualNetworkSettingsSection(
    networkMode: NetworkMode,
    onNetworkModeChange: (NetworkMode) -> Unit,
    pairingCode: String,
    onPairingCodeChange: (String) -> Unit,
    relayBaseUrl: String,
    onRelayBaseUrlChange: (String) -> Unit,
    hostAddress: String,
    onHostAddressChange: (String) -> Unit,
    hostPortStr: String,
    onHostPortChange: (String) -> Unit,
    bridgePortStr: String,
    onBridgePortChange: (String) -> Unit,
    heartbeatStr: String,
    onHeartbeatChange: (String) -> Unit,
    obsPassword: String,
    onObsPasswordChange: (String) -> Unit,
    showPassword: Boolean,
    onToggleShowPassword: () -> Unit,
    targetMicName: String,
    onTargetMicNameChange: (String) -> Unit,
    enableRelayFallback: Boolean,
    onToggleRelayFallback: (Boolean) -> Unit
) {
    Text(text = "Manual Network & Host Settings", style = MaterialTheme.typography.labelLarge)
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        FilterChip(
            selected = networkMode == NetworkMode.LAN,
            onClick = { onNetworkModeChange(NetworkMode.LAN) },
            label = { Text("LAN (Bridge / Direct OBS)") }
        )
        FilterChip(
            selected = networkMode == NetworkMode.INTERNET,
            onClick = { onNetworkModeChange(NetworkMode.INTERNET) },
            label = { Text("Internet (Relay)") }
        )
    }

    OutlinedTextField(
        value = pairingCode,
        onValueChange = onPairingCodeChange,
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
        onValueChange = onRelayBaseUrlChange,
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
        onValueChange = onHostAddressChange,
        label = { Text("OBS Host IP / Hostname Candidates") },
        placeholder = { Text("e.g. 192.168.1.50, pc.local") },
        supportingText = { Text("Comma or semicolon separated for automatic failover.") },
        singleLine = true,
        modifier = Modifier.fillMaxWidth()
    )

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        OutlinedTextField(
            value = hostPortStr,
            onValueChange = onHostPortChange,
            label = { Text("OBS Port") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.weight(1f)
        )
        OutlinedTextField(
            value = bridgePortStr,
            onValueChange = onBridgePortChange,
            label = { Text("Bridge Port") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.weight(1f)
        )
        OutlinedTextField(
            value = heartbeatStr,
            onValueChange = onHeartbeatChange,
            label = { Text("Heartbeat (s)") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            singleLine = true,
            modifier = Modifier.weight(1f)
        )
    }

    OutlinedTextField(
        value = obsPassword,
        onValueChange = onObsPasswordChange,
        label = { Text("OBS WebSocket Password") },
        singleLine = true,
        visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
        trailingIcon = {
            IconButton(onClick = onToggleShowPassword) {
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
        onValueChange = onTargetMicNameChange,
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
        Switch(checked = enableRelayFallback, onCheckedChange = onToggleRelayFallback)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KioskPinManagementCard(
    currentPin: String,
    onUpdatePin: (String) -> Unit
) {
    var showPinDialog by remember { mutableStateOf(false) }
    var currentPinInput by remember { mutableStateOf("") }
    var newPinInput by remember { mutableStateOf("") }
    var confirmPinInput by remember { mutableStateOf("") }
    var pinError by remember { mutableStateOf<String?>(null) }

    ExplorerCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f).padding(end = 8.dp)) {
                    Text(
                        text = "Classroom Kiosk PIN Lock",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = if (currentPin.isBlank()) "Not set (Connection Settings unlocked)" else "Active — PIN required to open Connection Settings",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                OutlinedButton(
                    onClick = {
                        currentPinInput = ""
                        newPinInput = ""
                        confirmPinInput = ""
                        pinError = null
                        showPinDialog = true
                    },
                    contentPadding = CompactExplorerButtonPadding
                ) {
                    Text(if (currentPin.isBlank()) "Set Kiosk PIN..." else "Set / Clear Kiosk PIN...", maxLines = 1, softWrap = false)
                }
            }
        }
    }

    if (showPinDialog) {
        AlertDialog(
            onDismissRequest = { showPinDialog = false },
            properties = DialogProperties(securePolicy = SecureFlagPolicy.SecureOn),
            title = { Text(if (currentPin.isBlank()) "Set Kiosk PIN" else "Change or Clear Kiosk PIN") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (currentPin.isNotBlank()) {
                        OutlinedTextField(
                            value = currentPinInput,
                            onValueChange = { currentPinInput = it; pinError = null },
                            label = { Text("Current Kiosk PIN") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    OutlinedTextField(
                        value = newPinInput,
                        onValueChange = { newPinInput = it; pinError = null },
                        label = { Text("New Kiosk PIN (leave blank to clear)") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        modifier = Modifier.fillMaxWidth()
                    )
                    if (newPinInput.isNotBlank()) {
                        OutlinedTextField(
                            value = confirmPinInput,
                            onValueChange = { confirmPinInput = it; pinError = null },
                            label = { Text("Confirm New PIN") },
                            singleLine = true,
                            visualTransformation = PasswordVisualTransformation(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                    if (!pinError.isNullOrEmpty()) {
                        Text(pinError!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                Button(onClick = {
                    val cleanNew = newPinInput.trim()
                    if (currentPin.isNotBlank() && currentPinInput.trim() != currentPin.trim()) {
                        pinError = "Current Kiosk PIN is incorrect."
                        return@Button
                    }
                    if (cleanNew.isNotEmpty() && cleanNew != confirmPinInput.trim()) {
                        pinError = "New PIN entries do not match."
                        return@Button
                    }
                    onUpdatePin(cleanNew)
                    showPinDialog = false
                }) { Text(if (newPinInput.isBlank() && currentPin.isNotBlank()) "Clear PIN" else "Save PIN") }
            },
            dismissButton = {
                OutlinedButton(onClick = { showPinDialog = false }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun ConnectionDialogActionFooter(
    initialConfig: RemoteConfig,
    formFactor: ResolvedFormFactor,
    networkMode: NetworkMode,
    hostAddress: String,
    bridgePortStr: String,
    sessionCodeInput: String,
    pairingCode: String,
    relayBaseUrl: String,
    hostPortStr: String,
    validationError: String?,
    statusText: String,
    testing: Boolean,
    onTestConnection: () -> Unit,
    onSaveAndReconnect: () -> Unit
) {
    val context = LocalContext.current
    var showShareQrDialog by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (!validationError.isNullOrEmpty()) {
            Text(
                text = validationError,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium
            )
        }

        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val ignoringBattery = pm?.isIgnoringBatteryOptimizations(context.packageName) ?: true
        if (!ignoringBattery) {
            BatteryOptimizationWarningCard(context = context)
        }

        OutlinedButton(
            onClick = { showShareQrDialog = true },
            contentPadding = CompactExplorerButtonPadding,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text("Share Pairing QR", maxLines = 1, softWrap = false)
        }

        if (showShareQrDialog) {
            val shareUri = remember(networkMode, hostAddress, bridgePortStr, sessionCodeInput, pairingCode, relayBaseUrl, hostPortStr) {
                buildSharePairingQrUri(
                    initialConfig = initialConfig,
                    networkMode = networkMode,
                    hostAddress = hostAddress,
                    bridgePortStr = bridgePortStr,
                    sessionCodeInput = sessionCodeInput,
                    pairingCode = pairingCode,
                    relayBaseUrl = relayBaseUrl,
                    hostPortStr = hostPortStr
                )
            }
            SharePairingQrDialog(shareUri = shareUri, onDismiss = { showShareQrDialog = false })
        }

        if (statusText.isNotEmpty()) {
            val statusColor = when {
                statusText.startsWith("✓") -> Color(0xFF10B981)
                statusText.startsWith("✕") || statusText.startsWith("Error:") -> MaterialTheme.colorScheme.error
                else -> MaterialTheme.colorScheme.primary
            }
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
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
                onClick = onTestConnection,
                enabled = !testing,
                contentPadding = CompactExplorerButtonPadding,
                modifier = Modifier.weight(1f)
            ) {
                if (testing) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
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
                onClick = onSaveAndReconnect,
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
    }
}

@Composable
private fun BatteryOptimizationWarningCard(context: Context) {
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

@Composable
private fun SharePairingQrDialog(
    shareUri: String,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
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
        onDismissRequest = onDismiss,
        properties = DialogProperties(securePolicy = SecureFlagPolicy.SecureOn),
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
            OutlinedButton(onClick = onDismiss) {
                Text("Close")
            }
        }
    )
}

internal fun buildSharePairingQrUri(
    initialConfig: RemoteConfig,
    networkMode: NetworkMode,
    hostAddress: String,
    bridgePortStr: String,
    sessionCodeInput: String,
    pairingCode: String,
    relayBaseUrl: String,
    hostPortStr: String
): String {
    return PairingUriBuilder.build(
        initialConfig.copy(
            networkMode = networkMode,
            hostAddress = hostAddress,
            bridgePort = bridgePortStr.toIntOrNull() ?: AppConstants.DEFAULT_BRIDGE_PORT,
            sessionPairingCode = sessionCodeInput,
            internetPairingCode = pairingCode,
            relayBaseUrl = relayBaseUrl,
            hostPort = hostPortStr.toIntOrNull() ?: AppConstants.DEFAULT_OBS_PORT,
            obsPassword = ""
        )
    )
}
