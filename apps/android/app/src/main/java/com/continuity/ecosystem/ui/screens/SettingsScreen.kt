package com.continuity.ecosystem.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsScreen(
    pairedMacName: String,
    onUnpairClicked: () -> Unit,
    hasAllFilesAccess: Boolean = true,
    hasNotificationListener: Boolean = true,
    hasCameraPermission: Boolean = true,
    hasNotificationPermission: Boolean = true,
    onRequestAllFilesAccess: () -> Unit = {},
    onRequestNotificationListener: () -> Unit = {},
    onRequestRuntimePermissions: () -> Unit = {}
) {
    var photoBackupEnabled by remember { mutableStateOf(true) }
    var filterSensitiveOtps by remember { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text(
            text = "Settings",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold
        )

        // Paired Mac Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "Trusted Mac",
                    fontSize = 12.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = pairedMacName.ifEmpty { "None paired" },
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold
                )

                if (pairedMacName.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(12.dp))
                    Button(
                        onClick = onUnpairClicked,
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
                    ) {
                        Text("Unpair Device")
                    }
                }
            }
        }

        // Permissions Diagnostics Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = "System Permissions & Access",
                    fontWeight = FontWeight.Bold
                )

                // 1. All Files Access
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("All Files Storage Access", fontWeight = FontWeight.Medium)
                        Text(
                            if (hasAllFilesAccess) "Granted - Full storage explorer active." else "Required for remote storage exploration.",
                            fontSize = 12.sp,
                            color = if (hasAllFilesAccess) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error
                        )
                    }
                    if (!hasAllFilesAccess) {
                        Button(onClick = onRequestAllFilesAccess) {
                            Text("Grant")
                        }
                    } else {
                        Text("✓ Active", color = Color(0xFF2E7D32), fontWeight = FontWeight.Bold)
                    }
                }

                HorizontalDivider()

                // 2. Notification Listener
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Notification Listener Service", fontWeight = FontWeight.Medium)
                        Text(
                            if (hasNotificationListener) "Granted - Mirroring notifications to Mac." else "Required to forward phone notifications.",
                            fontSize = 12.sp,
                            color = if (hasNotificationListener) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error
                        )
                    }
                    if (!hasNotificationListener) {
                        Button(onClick = onRequestNotificationListener) {
                            Text("Enable")
                        }
                    } else {
                        Text("✓ Active", color = Color(0xFF2E7D32), fontWeight = FontWeight.Bold)
                    }
                }

                HorizontalDivider()

                // 3. Camera Access
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Camera & HD Webcam", fontWeight = FontWeight.Medium)
                        Text(
                            if (hasCameraPermission) "Granted - Ready for Mac webcam relay." else "Required for phone-as-webcam streaming.",
                            fontSize = 12.sp,
                            color = if (hasCameraPermission) Color(0xFF2E7D32) else MaterialTheme.colorScheme.error
                        )
                    }
                    if (!hasCameraPermission) {
                        Button(onClick = onRequestRuntimePermissions) {
                            Text("Allow")
                        }
                    } else {
                        Text("✓ Active", color = Color(0xFF2E7D32), fontWeight = FontWeight.Bold)
                    }
                }
            }
        }

        // Privacy Section
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = "Privacy & Notifications",
                    fontWeight = FontWeight.Bold
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Redact 2FA & Banking OTPs", fontWeight = FontWeight.Medium)
                        Text(
                            "Prevent sensitive verification codes from forwarding to Mac.",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }
                    Switch(
                        checked = filterSensitiveOtps,
                        onCheckedChange = { filterSensitiveOtps = it }
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Automatic Media Backup", fontWeight = FontWeight.Medium)
                        Text(
                            "Incremental background backup over Wi-Fi when charging.",
                            fontSize = 12.sp,
                            color = Color.Gray
                        )
                    }
                    Switch(
                        checked = photoBackupEnabled,
                        onCheckedChange = { photoBackupEnabled = it }
                    )
                }
            }
        }

        // App Version Card
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "App Version",
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "v1.0.8 (Build 108)",
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
