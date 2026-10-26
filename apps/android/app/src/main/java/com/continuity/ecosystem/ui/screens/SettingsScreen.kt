package com.continuity.ecosystem.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsScreen(
    pairedMacName: String,
    onUnpairClicked: () -> Unit
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
                    text = "v1.0.5 (Build 105)",
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}
