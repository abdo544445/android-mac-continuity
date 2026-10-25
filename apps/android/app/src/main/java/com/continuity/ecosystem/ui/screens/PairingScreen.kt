package com.continuity.ecosystem.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LaptopMac
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.continuity.ecosystem.connection.DiscoveredPeer

@Composable
fun PairingScreen(
    discoveredPeers: List<DiscoveredPeer>,
    onPairPeerClicked: (DiscoveredPeer) -> Unit,
    onPairWithUri: (String) -> Unit
) {
    var manualUri by remember { mutableStateOf("") }
    var isCameraScannerActive by remember { mutableStateOf(false) }

    if (isCameraScannerActive) {
        CameraScannerOverlay(
            onQrScanned = { scannedUri ->
                isCameraScannerActive = false
                onPairWithUri(scannedUri)
            },
            onDismiss = {
                isCameraScannerActive = false
            }
        )
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Auto-Discovered Macs Section
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        text = "Nearby Macs on Local Network",
                        fontWeight = FontWeight.Bold,
                        fontSize = 16.sp,
                        color = MaterialTheme.colorScheme.primary
                    )

                    if (discoveredPeers.isEmpty()) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp
                            )
                            Text(
                                text = "Scanning local Wi-Fi network for Macs...",
                                fontSize = 13.sp,
                                color = Color.Gray
                            )
                        }
                    } else {
                        discoveredPeers.forEach { peer ->
                            Surface(
                                tonalElevation = 2.dp,
                                shape = RoundedCornerShape(10.dp),
                                modifier = Modifier.fillMaxWidth()
                            ) {
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                                    ) {
                                        Icon(
                                            imageVector = Icons.Default.LaptopMac,
                                            contentDescription = null,
                                            tint = MaterialTheme.colorScheme.primary
                                        )
                                        Column {
                                            Text(
                                                text = peer.deviceName,
                                                fontWeight = FontWeight.SemiBold,
                                                fontSize = 15.sp
                                            )
                                            Text(
                                                text = "${peer.ip}:${peer.tcpPort}",
                                                fontSize = 12.sp,
                                                color = Color.Gray
                                            )
                                        }
                                    }
                                    Button(onClick = { onPairPeerClicked(peer) }) {
                                        Text("Pair with PIN")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(4.dp))

            Icon(
                imageVector = Icons.Default.QrCodeScanner,
                contentDescription = null,
                modifier = Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary
            )

            Text(
                text = "Or Pair via QR Code",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = "Select a nearby Mac above for Bluetooth-style 6-digit PIN pairing, or scan the QR code shown on your Mac.",
                fontSize = 13.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            Button(
                onClick = {
                    isCameraScannerActive = true
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.QrCodeScanner,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Scan Mac QR Code", fontSize = 16.sp)
            }

            Text(
                text = "— OR ENTER MANUALLY —",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.outline
            )

            OutlinedTextField(
                value = manualUri,
                onValueChange = { manualUri = it },
                label = { Text("Paste pairing URL or IP") },
                placeholder = { Text("continuity://pair?v=1&host=192.168.1.10...") },
                modifier = Modifier.fillMaxWidth()
            )

            OutlinedButton(
                onClick = {
                    if (manualUri.isNotBlank()) {
                        onPairWithUri(manualUri)
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = manualUri.isNotBlank()
            ) {
                Text("Connect")
            }
        }
    }
}
