package com.continuity.ecosystem.connection

import android.content.Context
import android.content.Intent
import android.util.Log
import com.continuity.ecosystem.core.InputAction
import com.continuity.ecosystem.core.InputEvent
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

data class RemotePointerEvent(
    val action: InputAction,
    val normalizedX: Float,
    val normalizedY: Float
)

data class RemoteKeyEvent(
    val keyCode: Int,
    val text: String?
)

class HostControlHandler(private val context: Context) {

    private val _pointerEvents = MutableSharedFlow<RemotePointerEvent>(extraBufferCapacity = 64)
    val pointerEvents: SharedFlow<RemotePointerEvent> = _pointerEvents.asSharedFlow()

    private val _keyEvents = MutableSharedFlow<RemoteKeyEvent>(extraBufferCapacity = 64)
    val keyEvents: SharedFlow<RemoteKeyEvent> = _keyEvents.asSharedFlow()

    var onNavigationAction: ((InputAction) -> Unit)? = null

    fun handleInputEvent(event: InputEvent) {
        when (event.action) {
            InputAction.ACTION_DOWN,
            InputAction.ACTION_UP,
            InputAction.ACTION_MOVE -> {
                _pointerEvents.tryEmit(
                    RemotePointerEvent(
                        action = event.action,
                        normalizedX = event.normalizedX,
                        normalizedY = event.normalizedY
                    )
                )
            }
            InputAction.ACTION_KEY_DOWN,
            InputAction.ACTION_KEY_UP -> {
                _keyEvents.tryEmit(
                    RemoteKeyEvent(
                        keyCode = event.keyCode,
                        text = event.textInput
                    )
                )
            }
            InputAction.ACTION_NAV_BACK,
            InputAction.ACTION_NAV_HOME,
            InputAction.ACTION_NAV_RECENTS -> {
                onNavigationAction?.invoke(event.action) ?: run {
                    if (event.action == InputAction.ACTION_NAV_HOME) {
                        try {
                            val home = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            context.startActivity(home)
                        } catch (e: Exception) {
                            Log.w("HostControlHandler", "Failed launching home: ${e.message}")
                        }
                    }
                }
            }
        }
    }
}
