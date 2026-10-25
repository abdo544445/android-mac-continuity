package com.continuity.ecosystem.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.continuity.ecosystem.connection.DiscoveredPeer
import com.continuity.ecosystem.files.AndroidTransferItem

@Composable
fun HomeScreen(
    isConnected: Boolean,
    connectedMacName: String,
    discoveredPeers: List<DiscoveredPeer>,
    onPairPeerClicked: (DiscoveredPeer) -> Unit,
    onSendFileClicked: () -> Unit,
    onPushClipboardClicked: () -> Unit,
    onMirrorClicked: () -> Unit,
    onCameraClicked: () -> Unit,
    onExtendedDisplayClicked: (() -> Unit)? = null,
    onHandoffClicked: (() -> Unit)? = null,
    onFolderSyncClicked: (() -> Unit)? = null,
    transfers: List<AndroidTransferItem>
) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Status Card
        item {
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isConnected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
                )
            ) {
                Row(
                    modifier = Modifier.padding(20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    Icon(
                        imageVector = if (isConnected) Icons.Default.LaptopMac else Icons.Default.CloudOff,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = if (isConnected) MaterialTheme.colorScheme.primary else Color.Gray
                    )
                    Column {
                        Text(
                            text = if (isConnected) connectedMacName else "Not Connected",
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = if (isConnected) "Connected via Local Wi-Fi / USB-C" else "Waiting for Mac on local network",
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        // Auto-Discovered Nearby Macs on Local Network
        if (!isConnected && discoveredPeers.isNotEmpty()) {
            item {
                Text(
                    text = "Nearby Macs on Local Network",
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.height(8.dp))
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    discoveredPeers.forEach { peer ->
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.LaptopMac,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(32.dp)
                                    )
                                    Column {
                                        Text(
                                            text = peer.deviceName,
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 16.sp
                                        )
                                        Text(
                                            text = "${peer.ip}:${peer.tcpPort} • Auto-Detected",
                                            fontSize = 12.sp,
                                            color = Color.Gray
                                        )
                                    }
                                }
                                Button(onClick = { onPairPeerClicked(peer) }) {
                                    Text("Pair (PIN)")
                                }
                            }
                        }
                    }
                }
            }
        }

        // Quick Actions Grid
        item {
            Text(
                text = "Quick Actions",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.height(8.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                QuickActionButton(
                    title = "Send File",
                    icon = Icons.Default.UploadFile,
                    modifier = Modifier.weight(1f),
                    onClick = onSendFileClicked
                )
                QuickActionButton(
                    title = "Push Clipboard",
                    icon = Icons.Default.ContentPaste,
                    modifier = Modifier.weight(1f),
                    onClick = onPushClipboardClicked
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                QuickActionButton(
                    title = "Mirror Screen",
                    icon = Icons.Default.Cast,
                    modifier = Modifier.weight(1f),
                    onClick = onMirrorClicked
                )
                QuickActionButton(
                    title = "Webcam",
                    icon = Icons.Default.Videocam,
                    modifier = Modifier.weight(1f),
                    onClick = onCameraClicked
                )
            }
            if (isConnected) {
                Spacer(modifier = Modifier.height(12.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    QuickActionButton(
                        title = "Mac Display",
                        icon = Icons.Default.DesktopWindows,
                        modifier = Modifier.weight(1f),
                        onClick = { onExtendedDisplayClicked?.invoke() }
                    )
                    QuickActionButton(
                        title = "Folder Sync",
                        icon = Icons.Default.Sync,
                        modifier = Modifier.weight(1f),
                        onClick = { onFolderSyncClicked?.invoke() }
                    )
                }
            }
        }

        // Recent Transfers Header
        item {
            Text(
                text = "Recent Transfers",
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (transfers.isEmpty()) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(24.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "No transfers yet. Share files from any app.",
                            color = Color.Gray,
                            fontSize = 14.sp
                        )
                    }
                }
            }
        } else {
            items(transfers.take(5)) { item ->
                TransferItemCard(item)
            }
        }
    }
}

@Composable
fun QuickActionButton(
    title: String,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    ElevatedButton(
        onClick = onClick,
        modifier = modifier.height(64.dp),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(icon, contentDescription = null)
            Text(title, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
fun TransferItemCard(item: AndroidTransferItem) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = if (item.isIncoming) Icons.Default.ArrowDownward else Icons.Default.ArrowUpward,
                    contentDescription = null,
                    tint = if (item.isCompleted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(item.fileName, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Text(
                        text = "${item.bytesTransferred / 1024} KB / ${item.totalBytes / 1024} KB",
                        fontSize = 12.sp,
                        color = Color.Gray
                    )
                }
                Text(
                    text = if (item.isCompleted) "Done" else "${(item.progress * 100).toInt()}%",
                    fontWeight = FontWeight.Bold,
                    color = if (item.isCompleted) Color(0xFF4CAF50) else MaterialTheme.colorScheme.primary
                )
            }
            if (!item.isCompleted) {
                Spacer(modifier = Modifier.height(8.dp))
                LinearProgressIndicator(
                    progress = { item.progress },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
    }
}
