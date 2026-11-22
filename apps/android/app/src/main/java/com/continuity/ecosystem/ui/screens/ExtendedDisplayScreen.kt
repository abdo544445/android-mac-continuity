package com.continuity.ecosystem.ui.screens

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AspectRatio
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flip
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.core.ContinuityEnvelope
import com.continuity.ecosystem.core.InputAction
import com.continuity.ecosystem.core.InputEvent

@Composable
fun ExtendedDisplayScreen(
    currentFrameBitmap: Bitmap?,
    connectionService: ConnectionService?,
    onExit: () -> Unit
) {
    var componentSize by remember { mutableStateOf(IntSize.Zero) }
    var flipHorizontal by remember { mutableStateOf(false) }
    var fillScreen by remember { mutableStateOf(false) }
    var touchEnabled by remember { mutableStateOf(true) }
    var showHud by remember { mutableStateOf(true) }

    fun mapOffsetToNormalized(offset: Offset): Pair<Float, Float> {
        val boxW = componentSize.width.toFloat().coerceAtLeast(1f)
        val boxH = componentSize.height.toFloat().coerceAtLeast(1f)
        val bmp = currentFrameBitmap

        var renderW = boxW
        var renderH = boxH
        var offX = 0f
        var offY = 0f

        if (!fillScreen && bmp != null && bmp.width > 0 && bmp.height > 0) {
            val imgAspect = bmp.width.toFloat() / bmp.height.toFloat()
            val boxAspect = boxW / boxH
            if (imgAspect > boxAspect) {
                renderH = boxW / imgAspect
                offY = (boxH - renderH) / 2f
            } else {
                renderW = boxH * imgAspect
                offX = (boxW - renderW) / 2f
            }
        }

        var normX = ((offset.x - offX) / renderW.coerceAtLeast(1f)).coerceIn(0f, 1f)
        val normY = ((offset.y - offY) / renderH.coerceAtLeast(1f)).coerceIn(0f, 1f)
        if (flipHorizontal) {
            normX = 1f - normX
        }
        return normX to normY
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onSizeChanged { componentSize = it }
            .pointerInput(touchEnabled, flipHorizontal, fillScreen, currentFrameBitmap?.width, currentFrameBitmap?.height) {
                detectTapGestures { offset ->
                    if (!touchEnabled) return@detectTapGestures
                    val (nx, ny) = mapOffsetToNormalized(offset)
                    sendInput(connectionService, InputAction.ACTION_DOWN, nx, ny)
                    sendInput(connectionService, InputAction.ACTION_UP, nx, ny)
                }
            }
            .pointerInput(touchEnabled, flipHorizontal, fillScreen, currentFrameBitmap?.width, currentFrameBitmap?.height) {
                var lastDragPos = Offset.Zero
                detectDragGestures(
                    onDragStart = { startOffset ->
                        if (!touchEnabled) return@detectDragGestures
                        lastDragPos = startOffset
                        val (nx, ny) = mapOffsetToNormalized(startOffset)
                        sendInput(connectionService, InputAction.ACTION_DOWN, nx, ny)
                    },
                    onDrag = { change, _ ->
                        if (!touchEnabled) return@detectDragGestures
                        change.consume()
                        lastDragPos = change.position
                        val (nx, ny) = mapOffsetToNormalized(change.position)
                        sendInput(connectionService, InputAction.ACTION_MOVE, nx, ny)
                    },
                    onDragEnd = {
                        if (!touchEnabled) return@detectDragGestures
                        val (nx, ny) = mapOffsetToNormalized(lastDragPos)
                        sendInput(connectionService, InputAction.ACTION_UP, nx, ny)
                    },
                    onDragCancel = {
                        if (!touchEnabled) return@detectDragGestures
                        val (nx, ny) = mapOffsetToNormalized(lastDragPos)
                        sendInput(connectionService, InputAction.ACTION_UP, nx, ny)
                    }
                )
            }
    ) {
        if (currentFrameBitmap != null) {
            Image(
                bitmap = currentFrameBitmap.asImageBitmap(),
                contentDescription = "Mac Extended Display Stream",
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = if (flipHorizontal) -1f else 1f
                    },
                contentScale = if (fillScreen) ContentScale.Crop else ContentScale.Fit
            )
        } else {
            Column(
                modifier = Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CircularProgressIndicator(color = Color.White)
                Spacer(modifier = Modifier.height(16.dp))
                Text("Connecting to Mac DeskPad / Extended Display...", color = Color.White)
            }
        }

        // Top Floating Control Pill (Deskreen-inspired viewer controls)
        if (showHud) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 16.dp, start = 12.dp, end = 12.dp),
                shape = MaterialTheme.shapes.extraLarge,
                color = Color.Black.copy(alpha = 0.72f),
                tonalElevation = 4.dp
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Fullscreen,
                        contentDescription = null,
                        tint = Color(0xFF60A5FA)
                    )
                    Text(
                        text = "Mac Display",
                        color = Color.White,
                        style = MaterialTheme.typography.labelLarge
                    )

                    IconButton(onClick = { touchEnabled = !touchEnabled }) {
                        Icon(
                            imageVector = Icons.Default.TouchApp,
                            contentDescription = "Toggle Remote Touch",
                            tint = if (touchEnabled) Color(0xFF34D399) else Color.Gray
                        )
                    }

                    IconButton(onClick = { flipHorizontal = !flipHorizontal }) {
                        Icon(
                            imageVector = Icons.Default.Flip,
                            contentDescription = "Flip Horizontal",
                            tint = if (flipHorizontal) Color(0xFF60A5FA) else Color.White
                        )
                    }

                    IconButton(onClick = { fillScreen = !fillScreen }) {
                        Icon(
                            imageVector = Icons.Default.AspectRatio,
                            contentDescription = "Fit / Fill",
                            tint = if (fillScreen) Color(0xFF60A5FA) else Color.White
                        )
                    }

                    IconButton(onClick = { showHud = false }) {
                        Icon(
                            imageVector = Icons.Default.VisibilityOff,
                            contentDescription = "Hide Toolbar",
                            tint = Color.White
                        )
                    }

                    IconButton(
                        onClick = onExit,
                        colors = IconButtonDefaults.iconButtonColors(contentColor = Color(0xFFF87171))
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Exit"
                        )
                    }
                }
            }
        } else {
            IconButton(
                onClick = { showHud = true },
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp)
                    .background(Color.Black.copy(alpha = 0.45f), CircleShape)
            ) {
                Icon(
                    imageVector = Icons.Default.Visibility,
                    contentDescription = "Show Controls",
                    tint = Color.White.copy(alpha = 0.8f)
                )
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
