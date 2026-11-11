package com.xpprinter.xp_p323b

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.*
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val methodName = "xp_p323b/printer"
    private val shareName = "xp_p323b/share"
    private val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val usbAction get() = packageName + ".USB_PERMISSION"
    private var method: MethodChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var bt: BluetoothSocket? = null
    private var usb: UsbDeviceConnection? = null
    private var endpoint: UsbEndpoint? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == usbAction) {
                method?.invokeMethod("usbPermissionResult",
                    mapOf("granted" to intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)))
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(usbAction)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(usbReceiver, filter)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        method = MethodChannel(engine.dartExecutor.binaryMessenger, methodName)
        method?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "discoverDevices" -> result.success(discover())
                    "connect" -> {
                        val transport = call.argument<String>("transport") ?: "bluetooth"
                        val address = call.argument<String>("address") ?: error("Missing device")
                        if (transport == "usb") connectUsb(address) else connectBt(address)
                        result.success(true)
                    }
                    "write" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing bytes")
                        writeData(bytes); result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("PRINTER", e.message, null) }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, shareName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events; receiveShare(intent) }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        receiveShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent); receiveShare(intent)
    }

    private fun receiveShare(i: Intent?) {
        if (i == null || (i.action != Intent.ACTION_SEND && i.action != Intent.ACTION_SEND_MULTIPLE)) return
        val uris = mutableListOf<Uri>()
        if (i.action == Intent.ACTION_SEND_MULTIPLE) {
            val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33)
                i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") i.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            if (list != null) uris.addAll(list)
        } else {
            val uri: Uri? = if (Build.VERSION.SDK_INT >= 33)
                i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") i.getParcelableExtra(Intent.EXTRA_STREAM)
            if (uri != null) uris.add(uri)
        }
        val files = uris.mapIndexed { index, uri ->
            val file = File(cacheDir, "shared_" + System.currentTimeMillis() + "_" + index)
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Cannot read shared URI" }
                file.outputStream().use { output -> input.copyTo(output) }
            }
            mapOf("name" to file.name, "path" to file.absolutePath,
                "mimeType" to (contentResolver.getType(uri) ?: i.type ?: "application/octet-stream"))
        }
        sink?.success(mapOf("items" to files, "text" to i.getStringExtra(Intent.EXTRA_TEXT)))
    }

    private fun discover(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter != null && btPermission()) adapter.bondedDevices.forEach {
            out.add(mapOf("name" to (it.name ?: "Bluetooth printer"), "address" to it.address, "transport" to "bluetooth"))
        }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        manager.deviceList.values.forEach {
            out.add(mapOf("name" to (it.productName ?: "USB printer"), "address" to it.deviceId.toString(), "transport" to "usb"))
        }
        return out
    }

    private fun btPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val ok = ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
        if (!ok) ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN), 702)
        return ok
    }

    private fun connectBt(address: String) {
        check(btPermission()) { "Bluetooth permission requested; allow it then retry" }
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: error("Bluetooth unavailable")
        adapter.cancelDiscovery()
        val socket = adapter.getRemoteDevice(address).createRfcommSocketToServiceRecord(spp)
        socket.connect()
        bt?.close(); usb?.close(); bt = socket; usb = null
    }

    private fun connectUsb(id: String) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val device = manager.deviceList.values.firstOrNull { it.deviceId.toString() == id } ?: error("USB printer not found")
        if (!manager.hasPermission(device)) {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            manager.requestPermission(device, PendingIntent.getBroadcast(this, 0, Intent(usbAction), flags))
            error("USB permission requested. Allow access and tap Connect again.")
        }
        for (index in 0 until device.interfaceCount) {
            val intf = device.getInterface(index)
            for (e in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(e)
                if (ep.direction == UsbConstants.USB_DIR_OUT && ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    val connection = manager.openDevice(device) ?: error("Cannot open USB device")
                    check(connection.claimInterface(intf, true)) { "Cannot claim USB interface" }
                    bt?.close(); usb?.close(); bt = null; usb = connection; endpoint = ep
                    return
                }
            }
        }
        error("USB printer has no bulk output endpoint")
    }

    private fun writeData(bytes: ByteArray) {
        val socket = bt
        if (socket != null && socket.isConnected) {
            socket.outputStream.write(bytes); socket.outputStream.flush(); return
        }
        val connection = usb ?: error("Printer is not connected")
        val ep = endpoint ?: error("USB output endpoint missing")
        var offset = 0
        while (offset < bytes.size) {
            val part = bytes.copyOfRange(offset, minOf(offset + 16000, bytes.size))
            val count = connection.bulkTransfer(ep, part, part.size, 5000)
            check(count > 0) { "USB transfer failed" }; offset += count
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(usbReceiver) } catch (_: Exception) {}
        try { bt?.close() } catch (_: Exception) {}
        try { usb?.close() } catch (_: Exception) {}
        super.onDestroy()
    }
}
