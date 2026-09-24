package io.github.biptybop.netwho

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pendingLocation: MethodChannel.Result? = null

    // Android drops incoming multicast (mDNS/SSDP) unless an app holds this
    // lock, so the scanner takes it for the length of a scan.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netwho/multicast")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("netwho-scan").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    }
                    "release" -> {
                        multicastLock?.release()
                        multicastLock = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Android only reveals the Wi-Fi name to apps allowed to use
        // location; asked for only when the user taps "Show Wi-Fi name".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "netwho/location")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else if (pendingLocation != null) {
                    result.error("busy", "A permission request is already open", null)
                } else {
                    pendingLocation = result
                    requestPermissions(
                        arrayOf(
                            Manifest.permission.ACCESS_FINE_LOCATION,
                            Manifest.permission.ACCESS_COARSE_LOCATION,
                        ),
                        LOCATION_REQUEST,
                    )
                }
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LOCATION_REQUEST) return
        val granted = permissions.indices.any {
            permissions[it] == Manifest.permission.ACCESS_FINE_LOCATION &&
                grantResults.getOrNull(it) == PackageManager.PERMISSION_GRANTED
        }
        pendingLocation?.success(granted)
        pendingLocation = null
    }

    companion object {
        private const val LOCATION_REQUEST = 4201
    }

    override fun onDestroy() {
        multicastLock?.release()
        multicastLock = null
        super.onDestroy()
    }
}
