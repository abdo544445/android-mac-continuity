package com.continuity.ecosystem.connection

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.continuity.ecosystem.core.DeviceIdentity
import com.google.gson.Gson
import kotlinx.coroutines.*
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface

data class DiscoveredPeer(
    val deviceId: String,
    val deviceName: String,
    val platform: String,
    val ip: String,
    val tcpPort: Int,
    val publicKeyBase64: String,
    val lastSeenMs: Long = System.currentTimeMillis()
)

private data class DiscoveryWirePacket(
    val type: String,
    val deviceId: String,
    val deviceName: String,
    val platform: String,
    val ip: String,
    val tcpPort: Int,
    val publicKeyBase64: String,
    val pairingPin: String? = null
)

class LanDiscoveryManager(
    private val context: Context,
    private val identity: DeviceIdentity
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val gson = Gson()
    private val discoveryPort = 52402

    private var socket: DatagramSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var isRunning = false

    private val peersMap = mutableMapOf<String, DiscoveredPeer>()

    var onPeersUpdated: ((List<DiscoveredPeer>) -> Unit)? = null
    var onPairInviteReceived: ((DiscoveredPeer, String) -> Unit)? = null

    fun start() {
        if (isRunning) return
        isRunning = true

        try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wm?.createMulticastLock("ContinuityLanDiscovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w("ContinuityDebug", "Could not acquire MulticastLock: ${e.message}")
        }

        scope.launch {
            try {
                val sock = DatagramSocket(null).apply {
                    reuseAddress = true
                    broadcast = true
                    bind(InetSocketAddress(discoveryPort))
                }
                socket = sock
                Log.w("ContinuityDebug", "LanDiscoveryManager bound to UDP $discoveryPort")

                launch { receiveLoop(sock) }
                launch { broadcastLoop() }
            } catch (e: Exception) {
                Log.e("ContinuityDebug", "LanDiscoveryManager start failed: ${e.message}", e)
            }
        }
    }

    fun stop() {
        isRunning = false
        try {
            socket?.close()
        } catch (_: Exception) {}
        socket = null
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {}
    }

    private suspend fun broadcastLoop() {
        while (isRunning) {
            sendBeacon()
            pruneStalePeers()
            delay(2000)
        }
    }

    fun sendBeacon(targetHost: String? = null) {
        scope.launch {
            try {
                val sock = socket ?: return@launch
                val localIp = getLocalIpv4Address()
                val packetObj = DiscoveryWirePacket(
                    type = "CONTINUITY_BEACON",
                    deviceId = identity.deviceId,
                    deviceName = identity.deviceName,
                    platform = "PLATFORM_ANDROID",
                    ip = localIp,
                    tcpPort = 52400,
                    publicKeyBase64 = identity.getPublicKeyBase64(),
                    pairingPin = null
                )
                val bytes = gson.toJson(packetObj).toByteArray(Charsets.UTF_8)

                if (targetHost != null) {
                    val addr = InetAddress.getByName(targetHost)
                    sock.send(DatagramPacket(bytes, bytes.size, addr, discoveryPort))
                    return@launch
                }

                // 1. Broadcast to 255.255.255.255
                try {
                    val globalAddr = InetAddress.getByName("255.255.255.255")
                    sock.send(DatagramPacket(bytes, bytes.size, globalAddr, discoveryPort))
                } catch (_: Exception) {}

                // 2. Broadcast to subnet x.x.x.255
                val parts = localIp.split(".")
                if (parts.size == 4 && localIp != "127.0.0.1") {
                    val subnetBcast = "${parts[0]}.${parts[1]}.${parts[2]}.255"
                    try {
                        val subAddr = InetAddress.getByName(subnetBcast)
                        sock.send(DatagramPacket(bytes, bytes.size, subAddr, discoveryPort))
                    } catch (_: Exception) {}
                }
            } catch (e: Exception) {
                Log.w("ContinuityDebug", "sendBeacon error: ${e.message}")
            }
        }
    }

    private suspend fun receiveLoop(sock: DatagramSocket) {
        val buf = ByteArray(4096)
        while (isRunning && !sock.isClosed) {
            try {
                val pkt = DatagramPacket(buf, buf.size)
                sock.receive(pkt)
                val json = String(pkt.data, pkt.offset, pkt.length, Charsets.UTF_8)
                val wire = gson.fromJson(json, DiscoveryWirePacket::class.java) ?: continue

                // Ignore Android peers (only discover Macs)
                if (wire.platform != "PLATFORM_MACOS") continue

                val senderIp = pkt.address?.hostAddress ?: wire.ip
                val resolvedIp = if (wire.ip.isNotBlank() && wire.ip != "127.0.0.1" && wire.ip != "0.0.0.0") wire.ip else senderIp

                val peer = DiscoveredPeer(
                    deviceId = wire.deviceId,
                    deviceName = wire.deviceName,
                    platform = wire.platform,
                    ip = resolvedIp,
                    tcpPort = if (wire.tcpPort > 0) wire.tcpPort else 52400,
                    publicKeyBase64 = wire.publicKeyBase64,
                    lastSeenMs = System.currentTimeMillis()
                )

                val isNew: Boolean
                val snapshot: List<DiscoveredPeer>
                synchronized(peersMap) {
                    isNew = !peersMap.containsKey(peer.deviceId)
                    peersMap[peer.deviceId] = peer
                    snapshot = peersMap.values.sortedBy { it.deviceName }
                }

                if (isNew) {
                    Log.w("ContinuityDebug", "Auto-discovered Mac on LAN: ${peer.deviceName} (${peer.ip}:${peer.tcpPort})")
                    // Immediately reply with unicast beacon so the Mac sees us right away
                    sendBeacon(targetHost = resolvedIp)
                }

                withContext(Dispatchers.Main) {
                    onPeersUpdated?.invoke(snapshot)
                }

                if (wire.type == "CONTINUITY_PAIR_INVITE" && !wire.pairingPin.isNullOrBlank()) {
                    Log.w("ContinuityDebug", "Received CONTINUITY_PAIR_INVITE from ${peer.deviceName} with PIN ${wire.pairingPin}")
                    withContext(Dispatchers.Main) {
                        onPairInviteReceived?.invoke(peer, wire.pairingPin)
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.w("ContinuityDebug", "receiveLoop exception: ${e.message}")
                }
            }
        }
    }

    private suspend fun pruneStalePeers() {
        val now = System.currentTimeMillis()
        var changed = false
        var snapshot: List<DiscoveredPeer> = emptyList()
        synchronized(peersMap) {
            val iter = peersMap.entries.iterator()
            while (iter.hasNext()) {
                val entry = iter.next()
                if (now - entry.value.lastSeenMs > 12_000L) {
                    iter.remove()
                    changed = true
                }
            }
            if (changed) {
                snapshot = peersMap.values.sortedBy { it.deviceName }
            }
        }
        if (changed) {
            withContext(Dispatchers.Main) {
                onPeersUpdated?.invoke(snapshot)
            }
        }
    }

    private fun getLocalIpv4Address(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return "127.0.0.1"
            for (intf in interfaces) {
                if (!intf.isUp || intf.isLoopback) continue
                for (addr in intf.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val ip = addr.hostAddress ?: continue
                        if (!ip.startsWith("169.254.")) {
                            return ip
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return "127.0.0.1"
    }
}
