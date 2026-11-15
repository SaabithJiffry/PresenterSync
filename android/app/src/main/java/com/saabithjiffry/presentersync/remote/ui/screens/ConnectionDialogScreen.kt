package com.saabithjiffry.presentersync.remote.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.saabithjiffry.presentersync.remote.config.AppConstants
import com.saabithjiffry.presentersync.remote.config.NetworkMode
import com.saabithjiffry.presentersync.remote.config.RemoteConfig
import com.saabithjiffry.presentersync.remote.config.RemoteConfigStore
import com.saabithjiffry.presentersync.remote.network.ConnectionManager
import kotlinx.coroutines.launch

@Composable
fun ConnectionSettingsDialog(
    initialConfig: RemoteConfig,
    configStore: RemoteConfigStore,
    connectionManager: ConnectionManager,
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .widthIn(max = 680.dp)
                .fillMaxWidth(0.92f)
                .padding(vertical = 16.dp),
            shape = RoundedCornerShape(8.dp),
            color = MaterialTheme.colorScheme.surface,
            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
            tonalElevation = 0.dp
        ) {
            ConnectionSettingsForm(
                initialConfig = initialConfig,
                configStore = configStore,
                connectionManager = connectionManager,
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
    onDismiss: () -> Unit,
    onSaved: () -> Unit
) {
    val scope = rememberCoroutineScope()

    var networkMode by remember(initialConfig) { mutableStateOf(initialConfig.networkMode) }
    var pairingCode by remember(initialConfig) { mutableStateOf(initialConfig.internetPairingCode) }
    var hostAddress by remember(initialConfig) { mutableStateOf(initialConfig.hostAddress) }
    var hostPortStr by remember(initialConfig) { mutableStateOf(initialConfig.hostPort.toString()) }
    var obsPassword by remember(initialConfig) { mutableStateOf(initialConfig.obsPassword) }
    var showPassword by remember { mutableStateOf(false) }
    var targetMicName by remember(initialConfig) { mutableStateOf(initialConfig.targetMicName) }
    var heartbeatStr by remember(initialConfig) { mutableStateOf(initialConfig.heartbeatSeconds.toString()) }
    var enableRelayFallback by remember(initialConfig) { mutableStateOf(initialConfig.enableRelayFallback) }

    var testing by remember { mutableStateOf(false) }
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

        // Network mode chips
        Text(
            text = "Network Mode",
            style = MaterialTheme.typography.labelLarge
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FilterChip(
                selected = networkMode == NetworkMode.LAN,
                onClick = { networkMode = NetworkMode.LAN },
                label = { Text("LAN (Direct IP / .local)") }
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
            placeholder = { Text("e.g. a1b2c3d4") },
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
            horizontalArrangement = Arrangement.spacedBy(12.dp)
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
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            OutlinedButton(
                onClick = {
                    if (testing) return@OutlinedButton
                    validationError = null
                    testing = true
                    statusText = "Testing..."
                    scope.launch {
                        val res = connectionManager.testConnection(
                            networkMode = networkMode,
                            hostAddress = hostAddress,
                            portStr = hostPortStr,
                            password = obsPassword,
                            pairingCode = pairingCode,
                            onProgress = { msg -> statusText = msg }
                        )
                        statusText = res
                        testing = false
                    }
                },
                enabled = !testing,
                modifier = Modifier.weight(1f)
            ) {
                if (testing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text("Test Connection")
            }

            Button(
                onClick = {
                    val port = hostPortStr.trim().toIntOrNull()
                    if (port == null || port !in 1..65535) {
                        validationError = "OBS Port must be between 1 and 65535."
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
                            internetPairingCode = pairingCode.trim(),
                            hostAddress = hostAddress.trim(),
                            hostPort = port,
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
                modifier = Modifier.weight(1f)
            ) {
                Text("Save & Reconnect")
            }
        }
        } // end pinned footer column
    }
}
