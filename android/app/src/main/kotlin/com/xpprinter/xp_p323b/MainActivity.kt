package com.xpprinter.xp_p323b

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.*
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val methodName = "xp_p323b/printer"
    private val shareName = "xp_p323b/share"
    private val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val usbAction get() = packageName + ".USB_PERMISSION"
    private val usbResultAction get() = packageName + ".USB_PERMISSION_RESULT"
    private var method: MethodChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingShare: Map<String, Any?>? = null
    private var bt: BluetoothSocket? = null
    private var usb: UsbDeviceConnection? = null
    private var endpoint: UsbEndpoint? = null
    private val printerExecutor = Executors.newSingleThreadExecutor()

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == usbResultAction) {
                method?.invokeMethod(
                    "usbPermissionResult",
                    mapOf(
                        "granted" to intent.getBooleanExtra(
                            UsbManager.EXTRA_PERMISSION_GRANTED,
                            false,
                        ),
                    ),
                )
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(usbResultAction)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(usbReceiver, filter)
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        method = MethodChannel(engine.dartExecutor.binaryMessenger, methodName)
        method?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "discoverDevices" -> result.success(discover())
                    "connectionStatus" -> result.success(connectionStatus())
                    "restoreConnection" -> runPrinterTask(result) { restoreConnection() }
                    "getSettings" -> {
                        val prefs = getSharedPreferences("printer", MODE_PRIVATE)
                        result.success(
                            mapOf(
                                "paperWidthMm" to prefs.getInt("paperWidthMm", 80),
                                "paperWidthDots" to prefs.getInt("paperWidthDots", 576),
                                "printAlignment" to prefs.getString("printAlignment", "center"),
                            ),
                        )
                    }
                    "setPrintAlignment" -> {
                        val alignment = call.argument<String>("alignment") ?: "center"
                        require(alignment in listOf("right", "center", "left")) {
                            "Unsupported print alignment"
                        }
                        getSharedPreferences("printer", MODE_PRIVATE).edit()
                            .putString("printAlignment", alignment).apply()
                        result.success(true)
                    }
                    "setPaperWidth" -> {
                        val width = call.argument<Int>("paperWidthMm") ?: 80
                        val dots = call.argument<Int>("paperWidthDots") ?: if (width == 58) 392 else 576
                        require(width == 58 || width == 80) { "Unsupported paper width" }
                        require((width == 58 && (dots == 384 || dots == 392)) || (width == 80 && dots == 576)) { "Unsupported print width" }
                        getSharedPreferences("printer", MODE_PRIVATE).edit()
                            .putInt("paperWidthMm", width).putInt("paperWidthDots", dots).apply()
                        result.success(true)
                    }
                    "connect" -> {
                        val transport = call.argument<String>("transport") ?: "bluetooth"
                        val address = call.argument<String>("address") ?: error("Missing device")
                        val name = call.argument<String>("name") ?: "XP Printer"
                        runPrinterTask(result) {
                            if (transport == "usb") connectUsb(address, name) else connectBt(address, name)
                            connectionStatus()
                        }
                    }
                    "write" -> {
                        val bytes = call.argument<ByteArray>("bytes") ?: error("Missing bytes")
                        runPrinterTask(result) {
                            writeData(bytes)
                            true
                        }
                    }
                    "pdfPageCount" -> {
                        val path = call.argument<String>("path") ?: error("Missing PDF path")
                        Thread {
                            try {
                                val count = getPdfPageCount(path)
                                runOnUiThread { result.success(count) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PDF_COUNT", e.message, null) }
                            }
                        }.start()
                    }
                    "renderPdfPage" -> {
                        val path = call.argument<String>("path") ?: error("Missing PDF path")
                        val pageIndex = call.argument<Int>("pageIndex") ?: 0
                        val widthDots = call.argument<Int>("widthDots") ?: 576
                        Thread {
                            try {
                                val pagePath = renderPdfPage(path, pageIndex, widthDots)
                                runOnUiThread { result.success(pagePath) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("PDF_PAGE", e.message, null) }
                            }
                        }.start()
                    }
                    "renderPdf" -> {
                        val path = call.argument<String>("path") ?: error("Missing PDF path")
                        val widthDots = call.argument<Int>("widthDots") ?: 576
                        Thread {
                            try {
                                val pages = renderPdfPages(path, widthDots)
                                runOnUiThread { result.success(pages) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("PDF_RENDER", e.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("PRINTER", e.message, null)
            }
        }
        EventChannel(engine.dartExecutor.binaryMessenger, shareName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    sink = events
                    val pending = pendingShare
                    if (pending != null) {
                        events?.success(pending)
                        pendingShare = null
                    } else {
                        receiveShare(intent)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
    }

    private fun receiveShare(intent: Intent?) {
        if (intent == null ||
            (intent.action != Intent.ACTION_SEND &&
                intent.action != Intent.ACTION_SEND_MULTIPLE)
        ) return

        val uris = mutableListOf<Uri>()
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            if (list != null) uris.addAll(list)
        } else {
            val uri: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (uri != null) uris.add(uri)
        }

        val files = uris.mapIndexed { index, uri ->
            val file = File(cacheDir, "shared_" + System.currentTimeMillis() + "_" + index)
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Cannot read shared URI" }
                file.outputStream().use { output -> input.copyTo(output) }
            }
            mapOf(
                "name" to file.name,
                "path" to file.absolutePath,
                "mimeType" to (
                    contentResolver.getType(uri)
                        ?: intent.type
                        ?: "application/octet-stream"
                    ),
            )
        }
        val payload = mapOf(
            "items" to files,
            "text" to intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString(),
        )
        val eventSink = sink
        if (eventSink != null) {
            eventSink.success(payload)
        } else {
            pendingShare = payload
        }
    }

    private fun getPdfPageCount(path: String): Int {
        val pdfFile = File(path)
        require(pdfFile.isFile) { "PDF file not found" }
        val descriptor = ParcelFileDescriptor.open(
            pdfFile,
            ParcelFileDescriptor.MODE_READ_ONLY,
        )
        val renderer = PdfRenderer(descriptor)
        return try {
            require(renderer.pageCount in 1..40) {
                "PDF must contain between 1 and 40 pages"
            }
            renderer.pageCount
        } finally {
            renderer.close()
            descriptor.close()
        }
    }

    private fun renderPdfPage(path: String, pageIndex: Int, widthDots: Int): String {
        val pdfFile = File(path)
        require(pdfFile.isFile) { "PDF file not found" }
        val descriptor = ParcelFileDescriptor.open(
            pdfFile,
            ParcelFileDescriptor.MODE_READ_ONLY,
        )
        val renderer = PdfRenderer(descriptor)
        try {
            require(renderer.pageCount in 1..40) {
                "PDF must contain between 1 and 40 pages"
            }
            require(pageIndex in 0 until renderer.pageCount) { "Invalid PDF page index" }
            val page = renderer.openPage(pageIndex)
            try {
                val targetWidth = widthDots.coerceIn(384, 576)
                val scale = targetWidth.toFloat() / page.width.toFloat()
                val targetHeight = (page.height * scale).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(
                    targetWidth,
                    targetHeight,
                    Bitmap.Config.ARGB_8888,
                )
                try {
                    bitmap.eraseColor(Color.WHITE)
                    val transform = Matrix().apply { setScale(scale, scale) }
                    page.render(
                        bitmap,
                        null,
                        transform,
                        PdfRenderer.Page.RENDER_MODE_FOR_PRINT,
                    )
                    val output = File(
                        cacheDir,
                        "pdf_page_${System.currentTimeMillis()}_${pageIndex}.png",
                    )
                    output.outputStream().use { stream ->
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                            "Could not encode PDF page"
                        }
                    }
                    return output.absolutePath
                } finally {
                    bitmap.recycle()
                }
            } finally {
                page.close()
            }
        } finally {
            renderer.close()
            descriptor.close()
        }
    }

    private fun renderPdfPages(path: String, widthDots: Int): List<String> {
        val pdfFile = File(path)
        require(pdfFile.isFile) { "PDF file not found" }
        val descriptor = ParcelFileDescriptor.open(
            pdfFile,
            ParcelFileDescriptor.MODE_READ_ONLY,
        )
        val renderer = PdfRenderer(descriptor)
        val outputPaths = mutableListOf<String>()
        try {
            require(renderer.pageCount in 1..40) {
                "PDF must contain between 1 and 40 pages"
            }
            for (index in 0 until renderer.pageCount) {
                val page = renderer.openPage(index)
                try {
                    val targetWidth = widthDots.coerceIn(384, 576)
                    val scale = targetWidth.toFloat() / page.width.toFloat()
                    val targetHeight = (page.height * scale).toInt().coerceAtLeast(1)
                    val bitmap = Bitmap.createBitmap(
                        targetWidth,
                        targetHeight,
                        Bitmap.Config.ARGB_8888,
                    )
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        val transform = Matrix().apply { setScale(scale, scale) }
                        page.render(
                            bitmap,
                            null,
                            transform,
                            PdfRenderer.Page.RENDER_MODE_FOR_PRINT,
                        )
                        val output = File(
                            cacheDir,
                            "pdf_page_" + System.currentTimeMillis() + "_" + index + ".png",
                        )
                        output.outputStream().use { stream ->
                            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                                "Could not encode PDF page"
                            }
                        }
                        outputPaths.add(output.absolutePath)
                    } finally {
                        bitmap.recycle()
                    }
                } finally {
                    page.close()
                }
            }
        } finally {
            renderer.close()
            descriptor.close()
        }
        return outputPaths
    }

    private fun runPrinterTask(result: MethodChannel.Result, task: () -> Any?) {
        printerExecutor.execute {
            try {
                val value = task()
                runOnUiThread { result.success(value) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("PRINTER", error.message ?: "Printer operation failed", null)
                }
            }
        }
    }

    private fun discover(): List<Map<String, String>> {
        val output = mutableListOf<Map<String, String>>()
        val adapter = BluetoothAdapter.getDefaultAdapter()
        if (adapter != null && btPermission()) {
            if (!adapter.isEnabled) {
                // Ask Android to enable Bluetooth through the system confirmation UI.
                // The user remains in control; the app never silently toggles Bluetooth.
                startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
            } else {
                adapter.bondedDevices.forEach {
                    output.add(
                        mapOf(
                            "name" to (it.name ?: "Bluetooth printer"),
                            "address" to it.address,
                            "transport" to "bluetooth",
                            "deviceType" to bluetoothDeviceType(it.bluetoothClass),
                        ),
                    )
                }
            }
        }
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        manager.deviceList.values.forEach {
            output.add(
                mapOf(
                    "name" to (it.productName ?: "USB printer"),
                    "address" to usbDeviceKey(it),
                    "transport" to "usb",
                    "deviceType" to usbDeviceType(it),
                ),
            )
        }
        return output
    }

    private fun bluetoothDeviceType(deviceClass: BluetoothClass?): String =
        when (deviceClass?.majorDeviceClass) {
            BluetoothClass.Device.Major.PHONE -> "phone"
            BluetoothClass.Device.Major.AUDIO_VIDEO -> "audio"
            BluetoothClass.Device.Major.COMPUTER -> "computer"
            BluetoothClass.Device.Major.PERIPHERAL -> "printer"
            else -> "other"
        }

    private fun usbDeviceType(device: android.hardware.usb.UsbDevice): String {
        if (device.deviceClass == UsbConstants.USB_CLASS_PRINTER ||
            (0 until device.interfaceCount).any {
                device.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER
            }) return "printer"
        return when (device.deviceClass) {
            1 -> "audio"
            2 -> "phone"
            3 -> "computer"
            else -> "other"
        }
    }

    private fun btPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val granted = ActivityCompat.checkSelfPermission(
            this,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_SCAN,
                ),
                702,
            )
        }
        return granted
    }

    private fun saveLastPrinter(transport: String, address: String, name: String) {
        getSharedPreferences("printer", MODE_PRIVATE).edit()
            .putString("lastTransport", transport)
            .putString("lastAddress", address)
            .putString("lastName", name)
            .apply()
    }

    private fun connectionStatus(): Map<String, Any?> {
        val connected = (bt?.isConnected == true) || (usb != null)
        val prefs = getSharedPreferences("printer", MODE_PRIVATE)
        return mapOf(
            "connected" to connected,
            "name" to (prefs.getString("lastName", "XP Printer") ?: "XP Printer"),
            "address" to (prefs.getString("lastAddress", "") ?: ""),
            "transport" to (prefs.getString("lastTransport", "bluetooth") ?: "bluetooth"),
        )
    }

    private fun restoreConnection(): Map<String, Any?> {
        if ((bt?.isConnected == true) || usb != null) return connectionStatus()
        val prefs = getSharedPreferences("printer", MODE_PRIVATE)
        val address = prefs.getString("lastAddress", null) ?: return connectionStatus()
        val transport = prefs.getString("lastTransport", "bluetooth") ?: "bluetooth"
        val name = prefs.getString("lastName", "XP Printer") ?: "XP Printer"
        try {
            if (transport == "usb") connectUsb(address, name) else connectBt(address, name)
        } catch (_: Exception) {
            // Keep the saved printer so the user can retry after granting permissions.
        }
        return connectionStatus()
    }

    private fun connectBt(address: String, name: String) {
        check(btPermission()) { "Bluetooth permission requested; allow it then retry" }
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: error("Bluetooth unavailable")
        adapter.cancelDiscovery()
        val socket = adapter.getRemoteDevice(address)
            .createRfcommSocketToServiceRecord(spp)
        socket.connect()
        bt?.close()
        usb?.close()
        bt = socket
        usb = null
        endpoint = null
        saveLastPrinter("bluetooth", address, name)
    }

    private fun connectUsb(id: String, name: String) {
        val manager = getSystemService(Context.USB_SERVICE) as UsbManager
        val available = manager.deviceList.values.toList()
        val device = available.firstOrNull { usbDeviceKey(it) == id }
            ?: run {
                val parts = id.split(":")
                val matches = if (parts.size >= 3 && parts[0] == "usb") {
                    available.filter {
                        it.vendorId.toString() == parts[1] && it.productId.toString() == parts[2]
                    }
                } else emptyList()
                matches.singleOrNull()
            }
            ?: error("USB device is no longer connected. Reconnect the cable and search again.")

        if (!manager.hasPermission(device)) {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            manager.requestPermission(
                device,
                PendingIntent.getBroadcast(
                    this,
                    0,
                    Intent(this, UsbPermissionReceiver::class.java).setAction(usbAction),
                    flags,
                ),
            )
            error("USB permission requested. Allow access and tap Connect again.")
        }

        for (index in 0 until device.interfaceCount) {
            val intf = device.getInterface(index)
            for (endpointIndex in 0 until intf.endpointCount) {
                val usbEndpoint = intf.getEndpoint(endpointIndex)
                if (usbEndpoint.direction == UsbConstants.USB_DIR_OUT &&
                    usbEndpoint.type == UsbConstants.USB_ENDPOINT_XFER_BULK
                ) {
                    val connection = manager.openDevice(device)
                        ?: error("Cannot open USB device")
                    check(connection.claimInterface(intf, true)) {
                        "Cannot claim USB interface"
                    }
                    bt?.close()
                    usb?.close()
                    bt = null
                    usb = connection
                    endpoint = usbEndpoint
                    saveLastPrinter("usb", id, name)
                    return
                }
            }
        }
        error("USB printer has no bulk output endpoint")
    }

    private fun usbDeviceKey(device: android.hardware.usb.UsbDevice): String =
        "usb:" + device.vendorId + ":" + device.productId + ":" + device.deviceName

    private fun writeData(bytes: ByteArray) {
        val socket = bt
        if (socket != null && socket.isConnected) {
            val output = socket.outputStream
            // Keep each Bluetooth write bounded; flush once to avoid per-chunk latency.
            var offset = 0
            while (offset < bytes.size) {
                val end = minOf(offset + 16_384, bytes.size)
                output.write(bytes, offset, end - offset)
                offset = end
            }
            output.flush()
            return
        }

        val connection = usb ?: error("Printer is not connected")
        val usbEndpoint = endpoint ?: error("USB output endpoint missing")
        var offset = 0
        while (offset < bytes.size) {
            val part = bytes.copyOfRange(offset, minOf(offset + 16000, bytes.size))
            val count = connection.bulkTransfer(
                usbEndpoint,
                part,
                part.size,
                5000,
            )
            check(count > 0) { "USB transfer failed" }
            offset += count
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(usbReceiver)
        } catch (_: Exception) {
        }
        try {
            bt?.close()
        } catch (_: Exception) {
        }
        try {
            usb?.close()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
