package com.continuity.ecosystem.ui.screens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.MotionEvent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.InputEvent
import com.continuity.ecosystem.core.InputAction

@Composable
fun ExtendedDisplayScreen(
    currentFrameBitmap: Bitmap?,
    connectionService: ConnectionService?,
    onExit: () -> Unit
) {
    var componentSize by remember { mutableStateOf(IntSize.Zero) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onSizeChanged { componentSize = it }
            .pointerInput(Unit) {
                detectTapGestures { offset ->
                    if (componentSize.width > 0 && componentSize.height > 0) {
                        val normX = (offset.x / componentSize.width).coerceIn(0f, 1f)
                        val normY = (offset.y / componentSize.height).coerceIn(0f, 1f)
                        sendInput(connectionService, InputAction.ACTION_DOWN, normX, normY)
                    }
                }
            }
    ) {
        if (currentFrameBitmap != null) {
            Image(
                bitmap = currentFrameBitmap.asImageBitmap(),
                contentDescription = "Mac Extended Display Stream",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        } else {
            Column(
                modifier = Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(color = Color.White)
                Spacer(modifier = Modifier.height(16.dp))
                Text("Connecting to Mac Extended Display...", color = Color.White)
            }
        }

        // Top Toolbar Overlay
        Surface(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 16.dp),
            shape = MaterialTheme.shapes.extraLarge,
            color = Color.Black.copy(alpha = 0.65f),
            tonalElevation = 4.dp
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Fullscreen,
                    contentDescription = null,
                    tint = Color.White
                )
                Text(
                    text = "Mac Secondary Display (Interactive)",
                    color = Color.White,
                    style = MaterialTheme.typography.bodyMedium
                )
                IconButton(
                    onClick = onExit,
                    colors = IconButtonDefaults.iconButtonColors(contentColor = Color.White)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Exit"
                    )
                }
            }
        }
    }
}

private fun sendInput(service: ConnectionService?, action: InputAction, normX: Float, normY: Float) {
    service?.sendEnvelope(
        ContinuityEnvelope(
            senderDeviceId = "android",
            inputEvent = InputEvent(
                sessionId = "ext_display",
                action = action,
                normalizedX = normX,
                normalizedY = normY
            )
        )
    )
}
