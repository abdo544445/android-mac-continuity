package com.continuity.ecosystem.ui.screens

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.continuity.ecosystem.camera.CameraStreamingService
import com.continuity.ecosystem.connection.ConnectionService
import com.continuity.ecosystem.connection.RawBinaryChunk
import com.continuity.ecosystem.core.CameraControlRequest
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

@Composable
fun ContinuityWebcamScreen(
    macName: String,
    remoteCameraControl: CameraControlRequest? = null,
    onClose: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        )
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { isGranted ->
        hasCameraPermission = isGranted
    }

    var isFrontCamera by remember { mutableStateOf(false) }
    var isTorchOn by remember { mutableStateOf(false) }
    var zoomRatio by remember { mutableStateOf(1.0f) }
    var exposureCompensation by remember { mutableStateOf(0) }
    var showGridOverlay by remember { mutableStateOf(false) }
    var showProControls by remember { mutableStateOf(false) }

    var cameraControl by remember { mutableStateOf<CameraControl?>(null) }
    var cameraInfo by remember { mutableStateOf<CameraInfo?>(null) }
    val previewView = remember { PreviewView(context) }

    val cameraExecutor = remember { Executors.newSingleThreadExecutor() }
    val lastFrameTimeMs = remember { AtomicLong(0L) }
    val frameCounter = remember { AtomicInteger(0) }

    // Sync remote commands from Mac
    LaunchedEffect(remoteCameraControl) {
        val ctrl = remoteCameraControl ?: return@LaunchedEffect
        ctrl.torch?.let { t ->
            if (!isFrontCamera) {
                isTorchOn = t
                cameraControl?.enableTorch(t)
            }
        }
        ctrl.zoomRatio?.let { z ->
            zoomRatio = z
            cameraControl?.setZoomRatio(z)
        }
        ctrl.exposureCompensation?.let { ev ->
            exposureCompensation = ev
            cameraControl?.setExposureCompensationIndex(ev)
        }
        ctrl.lens?.let { lens ->
            val wantFront = (lens.uppercase() == "FRONT")
            if (isFrontCamera != wantFront) {
                isFrontCamera = wantFront
                isTorchOn = false
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            cameraExecutor.shutdown()
        }
    }

    LaunchedEffect(hasCameraPermission) {
        if (!hasCameraPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        } else {
            val serviceIntent = Intent(context, CameraStreamingService::class.java)
            context.startForegroundService(serviceIntent)
        }
    }

    // Bind Camera lifecycle
    LaunchedEffect(hasCameraPermission, isFrontCamera) {
        if (!hasCameraPermission) return@LaunchedEffect

        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                val cameraProvider = cameraProviderFuture.get()
                val preview = Preview.Builder().build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

                val cameraSelector = if (isFrontCamera) {
                    CameraSelector.DEFAULT_FRONT_CAMERA
                } else {
                    CameraSelector.DEFAULT_BACK_CAMERA
                }

                val imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(android.util.Size(1280, 720))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .build()

                imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                    try {
                        val now = System.currentTimeMillis()
                        // Stream ~25 FPS to Mac
                        if (now - lastFrameTimeMs.get() >= 40L) {
                            lastFrameTimeMs.set(now)
                            val bmp = imageProxy.toBitmap()
                            val matrix = Matrix().apply {
                                postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                            }
                            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
                            val out = ByteArrayOutputStream(40960)
                            rotated.compress(Bitmap.CompressFormat.JPEG, 65, out)
                            val bytes = out.toByteArray()
                            if (rotated !== bmp) {
                                rotated.recycle()
                            }
                            bmp.recycle()

                            ConnectionService.activeInstance?.sendStreamChunk(
                                RawBinaryChunk(
                                    transferId = "00000000-0000-0000-0000-000000CAMERA",
                                    chunkIndex = frameCounter.getAndIncrement(),
                                    chunkTotal = 1,
                                    data = bytes
                                )
                            )
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("WebcamScreen", "Frame analysis exception: ${e.message}")
                    } finally {
                        try {
                            imageProxy.close()
                        } catch (_: Exception) {}
                    }
                }

                cameraProvider.unbindAll()
                val cam = cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalysis
                )
                cameraControl = cam.cameraControl
                cameraInfo = cam.cameraInfo

                // Re-apply active state
                cam.cameraControl.setZoomRatio(zoomRatio)
                if (!isFrontCamera && isTorchOn) {
                    cam.cameraControl.enableTorch(true)
                }
            } catch (e: Exception) {
                android.util.Log.e("WebcamScreen", "Binding failed: ${e.message}", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        if (hasCameraPermission) {
            AndroidView(
                factory = { previewView },
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures { offset ->
                            val factory = previewView.meteringPointFactory
                            val point = factory.createPoint(offset.x, offset.y)
                            val action = FocusMeteringAction.Builder(point).build()
                            cameraControl?.startFocusAndMetering(action)
                        }
                    }
            )

            // Rule of Thirds Grid Overlay
            if (showGridOverlay) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val w = size.width
                    val h = size.height
                    val gridColor = Color.White.copy(alpha = 0.35f)
                    val strokeW = 1.5f

                    // Vertical lines
                    drawLine(gridColor, Offset(w / 3f, 0f), Offset(w / 3f, h), strokeWidth = strokeW)
                    drawLine(gridColor, Offset(2f * w / 3f, 0f), Offset(2f * w / 3f, h), strokeWidth = strokeW)

                    // Horizontal lines
                    drawLine(gridColor, Offset(0f, h / 3f), Offset(w, h / 3f), strokeWidth = strokeW)
                    drawLine(gridColor, Offset(0f, 2f * h / 3f), Offset(w, 2f * h / 3f), strokeWidth = strokeW)
                }
            }

            // Top Status Overlay
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 48.dp, start = 20.dp, end = 20.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(
                    onClick = {
                        val stopIntent = Intent(context, CameraStreamingService::class.java)
                        context.stopService(stopIntent)
                        onClose()
                    },
                    modifier = Modifier.background(Color.Black.copy(alpha = 0.5f), CircleShape)
                ) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close Camera",
                        tint = Color.White
                    )
                }

                Surface(
                    color = Color.Black.copy(alpha = 0.65f),
                    shape = RoundedCornerShape(20.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Box(
                            modifier = Modifier
                                .size(10.dp)
                                .background(Color(0xFFFF3B30), CircleShape)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Webcam Live: ${if (macName.isNotBlank()) macName else "Mac"}",
                            color = Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                // Grid Toggle Button
                IconButton(
                    onClick = { showGridOverlay = !showGridOverlay },
                    modifier = Modifier.background(Color.Black.copy(alpha = 0.5f), CircleShape)
                ) {
                    Icon(
                        imageVector = if (showGridOverlay) Icons.Default.GridOn else Icons.Default.GridOff,
                        contentDescription = "Toggle Grid",
                        tint = if (showGridOverlay) Color(0xFF0A84FF) else Color.White
                    )
                }
            }

            // Pro Controls Expandable Deck
            if (showProControls) {
                Surface(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 120.dp, start = 20.dp, end = 20.dp)
                        .fillMaxWidth(),
                    color = Color.Black.copy(alpha = 0.85f),
                    shape = RoundedCornerShape(20.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            text = "PRO CAMERA CONTROLS",
                            color = Color.White.copy(alpha = 0.7f),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold
                        )

                        // Zoom Slider
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text("Zoom", color = Color.White, fontSize = 12.sp, modifier = Modifier.width(42.dp))
                            Slider(
                                value = zoomRatio,
                                onValueChange = { z ->
                                    zoomRatio = z
                                    cameraControl?.setZoomRatio(z)
                                },
                                valueRange = 1.0f..8.0f,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = String.format("%.1fx", zoomRatio),
                                color = Color.Yellow,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                modifier = Modifier.width(40.dp)
                            )
                        }

                        // EV Exposure Slider
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Text("EV", color = Color.White, fontSize = 12.sp, modifier = Modifier.width(42.dp))
                            Slider(
                                value = exposureCompensation.toFloat(),
                                onValueChange = { ev ->
                                    val evInt = ev.toInt()
                                    exposureCompensation = evInt
                                    cameraControl?.setExposureCompensationIndex(evInt)
                                },
                                valueRange = -4f..4f,
                                steps = 7,
                                modifier = Modifier.weight(1f)
                            )
                            Text(
                                text = String.format("%+d EV", exposureCompensation),
                                color = Color.White,
                                fontSize = 12.sp,
                                modifier = Modifier.width(44.dp)
                            )
                        }

                        // Quick Zoom Preset Buttons
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            listOf(1.0f, 2.0f, 5.0f).forEach { z ->
                                FilterChip(
                                    selected = (zoomRatio == z),
                                    onClick = {
                                        zoomRatio = z
                                        cameraControl?.setZoomRatio(z)
                                    },
                                    label = { Text(String.format("%.0fx", z)) },
                                    colors = FilterChipDefaults.filterChipColors(
                                        labelColor = Color.White,
                                        selectedLabelColor = Color.Black,
                                        selectedContainerColor = Color(0xFF0A84FF)
                                    )
                                )
                            }
                        }
                    }
                }
            }

            // Bottom Control Toolbar
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 36.dp, start = 20.dp, end = 20.dp),
                color = Color.Black.copy(alpha = 0.75f),
                shape = RoundedCornerShape(28.dp)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(20.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Torch Toggle
                    IconButton(
                        onClick = {
                            if (!isFrontCamera) {
                                isTorchOn = !isTorchOn
                                cameraControl?.enableTorch(isTorchOn)
                            }
                        },
                        enabled = !isFrontCamera
                    ) {
                        Icon(
                            imageVector = if (isTorchOn) Icons.Default.FlashOn else Icons.Default.FlashOff,
                            contentDescription = "Toggle Torch",
                            tint = if (isTorchOn) Color(0xFFFFD60A) else Color.White
                        )
                    }

                    // Flip Camera (Front / Back)
                    IconButton(
                        onClick = {
                            isFrontCamera = !isFrontCamera
                            isTorchOn = false
                        }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Cameraswitch,
                            contentDescription = "Switch Camera",
                            tint = Color.White
                        )
                    }

                    // Pro Controls Toggle
                    IconButton(
                        onClick = { showProControls = !showProControls }
                    ) {
                        Icon(
                            imageVector = Icons.Default.Tune,
                            contentDescription = "Pro Camera Controls",
                            tint = if (showProControls) Color(0xFF0A84FF) else Color.White
                        )
                    }
                }
            }
        } else {
            // Permission Required View
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = "Camera Permission Required",
                    color = Color.White,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Allow camera access to use your phone as a high-definition webcam for your Mac.",
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 14.sp,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) },
                    colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
                ) {
                    Text("Grant Camera Permission")
                }
                Spacer(modifier = Modifier.height(12.dp))
                TextButton(onClick = onClose) {
                    Text("Cancel", color = Color.White)
                }
            }
        }
    }
}
