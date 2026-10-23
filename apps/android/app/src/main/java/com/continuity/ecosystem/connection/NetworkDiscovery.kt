package com.continuity.ecosystem.connection

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

class NetworkDiscovery(context: Context) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val serviceType = "_continuity._tcp."
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    var onServiceFound: ((host: String, port: Int, serviceName: String) -> Unit)? = null

    fun startDiscovery() {
        stopDiscovery()

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d("ContinuityNSD", "Service discovery started: $regType")
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                Log.d("ContinuityNSD", "Discovered: ${service.serviceName}")
                if (service.serviceType.contains("_continuity")) {
                    nsdManager.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                            Log.e("ContinuityNSD", "Resolve failed: $errorCode")
                        }

                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val host = serviceInfo.host.hostAddress ?: return
                            val port = serviceInfo.port
                            Log.d("ContinuityNSD", "Resolved: $host:$port")
                            onServiceFound?.invoke(host, port, serviceInfo.serviceName)
                        }
                    })
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                Log.d("ContinuityNSD", "Service lost: ${service.serviceName}")
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.d("ContinuityNSD", "Discovery stopped")
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e("ContinuityNSD", "Start discovery failed: $errorCode")
                stopDiscovery()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e("ContinuityNSD", "Stop discovery failed: $errorCode")
            }
        }

        try {
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.e("ContinuityNSD", "Error initiating discovery: ${e.message}")
        }
    }

    fun stopDiscovery() {
        discoveryListener?.let {
            try {
                nsdManager.stopServiceDiscovery(it)
            } catch (e: Exception) {
                // Ignore if already stopped
            }
        }
        discoveryListener = null
    }
}
