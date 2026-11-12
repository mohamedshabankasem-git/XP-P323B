package com.xpprinter.xp_p323b

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import androidx.core.content.ContextCompat
import java.util.UUID
import java.util.concurrent.Executors

/** Android system print-framework bridge for paired Bluetooth ESC/POS printers. */
class XPPrintService : PrintService() {
    private val spp = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var activeSocket: BluetoothSocket? = null
    @Volatile private var cancelRequested = false

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession =
        XpPrinterDiscoverySession()

    override fun onPrintJobQueued(printJob: PrintJob) {
        cancelRequested = false
        val descriptor = try {
            printJob.document.data
        } catch (error: Exception) {
            printJob.fail("تعذر قراءة ملف الطباعة: ${error.message}")
            return
        }
        val localId = printJob.info.printerId.localId
        val address = localId.substringAfter('|', "")
        if (address.isBlank()) {
            try { descriptor.close() } catch (_: Exception) {}
            printJob.fail("عنوان الطابعة غير صالح")
            return
        }
        if (!printJob.start()) {
            try { descriptor.close() } catch (_: Exception) {}
            return
        }
        executor.execute {
            var failure: String? = null
            try {
                printPdf(descriptor, address, printJob.info.attributes?.mediaSize?.id)
            } catch (error: Exception) {
                failure = error.message ?: "فشلت الطباعة"
            } finally {
                try { descriptor.close() } catch (_: Exception) {}
                try { activeSocket?.close() } catch (_: Exception) {}
                activeSocket = null
            }
            mainHandler.post {
                if (cancelRequested) printJob.cancel()
                else if (failure == null) printJob.complete()
                else printJob.fail(failure!!)
            }
        }
    }

    override fun onRequestCancelPrintJob(printJob: PrintJob) {
        cancelRequested = true
        try { activeSocket?.close() } catch (_: Exception) {}
        if (printJob.isQueued || printJob.isStarted || printJob.isBlocked) {
            printJob.cancel()
        }
    }

    private fun printPdf(
        descriptor: ParcelFileDescriptor,
        address: String,
        selectedMediaId: String?
    ) {
        val device = BluetoothAdapter.getDefaultAdapter()?.getRemoteDevice(address)
            ?: error("تعذر العثور على طابعة Bluetooth")
        val socket = device.createRfcommSocketToServiceRecord(spp)
        activeSocket = socket
        socket.connect()

        val prefs = getSharedPreferences("printer", MODE_PRIVATE)
        val configuredDots = prefs.getInt("paperWidthDots", 384)
        val paperDots = when (selectedMediaId) {
            "thermal_80" -> 576
            "thermal_58" -> if (configuredDots == 400) 400 else 384
            else -> when (configuredDots) { 400 -> 400; 576 -> 576; else -> 384 }
        }
        val renderer = PdfRenderer(descriptor)
        try {
            require(renderer.pageCount in 1..100) { "عدد صفحات الملف غير مدعوم" }
            val output = socket.outputStream
            output.write(byteArrayOf(0x1B, 0x40))
            for (pageIndex in 0 until renderer.pageCount) {
                check(!cancelRequested) { "تم إلغاء الطباعة" }
                val page = renderer.openPage(pageIndex)
                try {
                    val printableWidth = paperDots - LEFT_MARGIN
                    val scale = printableWidth.toFloat() / page.width
                    val height = (page.height * scale).toInt().coerceIn(1, MAX_PAGE_HEIGHT)
                    val bitmap = Bitmap.createBitmap(paperDots, height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        val transform = Matrix().apply {
                            setScale(scale, scale)
                            postTranslate(LEFT_MARGIN.toFloat(), 0f)
                        }
                        page.render(bitmap, null, transform, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                        output.write(bitmapToEscPos(bitmap))
                        output.flush()
                    } finally {
                        bitmap.recycle()
                    }
                } finally {
                    page.close()
                }
            }
            output.write(byteArrayOf(0x0A, 0x0A))
            output.flush()
        } finally {
            renderer.close()
        }
    }

    private fun bitmapToEscPos(bitmap: Bitmap): ByteArray {
        val widthBytes = (bitmap.width + 7) / 8
        val pixels = ByteArray(widthBytes * bitmap.height)
        for (y in 0 until bitmap.height) {
            for (x in 0 until bitmap.width) {
                val color = bitmap.getPixel(x, y)
                val luminance = (Color.red(color) * 299 + Color.green(color) * 587 +
                    Color.blue(color) * 114) / 1000
                if (luminance < THRESHOLD) {
                    val index = y * widthBytes + x / 8
                    pixels[index] = (pixels[index].toInt() or (0x80 shr (x % 8))).toByte()
                }
            }
        }
        val header = byteArrayOf(
            0x1B, 0x61, 0x00,
            0x1D, 0x76, 0x30, 0x00,
            (widthBytes and 0xFF).toByte(), ((widthBytes shr 8) and 0xFF).toByte(),
            (bitmap.height and 0xFF).toByte(), ((bitmap.height shr 8) and 0xFF).toByte()
        )
        return header + pixels + byteArrayOf(0x0A)
    }

    private inner class XpPrinterDiscoverySession : PrinterDiscoverySession() {
        override fun onStartPrinterDiscovery(priorityList: MutableList<PrinterId>?) {
            addPrinters(discoverPrinters())
        }
        override fun onStopPrinterDiscovery() = Unit
        override fun onValidatePrinters(printerIds: MutableList<PrinterId>?) {
            addPrinters(discoverPrinters().filter { printerIds == null || printerIds.contains(it.id) })
        }
        override fun onStartPrinterStateTracking(printerId: PrinterId) {
            addPrinters(discoverPrinters().filter { it.id == printerId })
        }
        override fun onStopPrinterStateTracking(printerId: PrinterId) = Unit
        override fun onDestroy() = Unit

        private fun discoverPrinters(): List<PrinterInfo> {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
            if (Build.VERSION.SDK_INT >= 31 &&
                ContextCompat.checkSelfPermission(this@XPPrintService, Manifest.permission.BLUETOOTH_CONNECT)
                    != PackageManager.PERMISSION_GRANTED
            ) return emptyList()
            return try {
                adapter.bondedDevices.orEmpty().filter { isLikelyPrinter(it) }.map { device ->
                    val id = generatePrinterId("bt|${device.address}")
                    val prefs = getSharedPreferences("printer", MODE_PRIVATE)
                    val defaultWide = prefs.getInt("paperWidthMm", 58) == 80
                    val narrow = PrintAttributes.MediaSize("thermal_58", "58 mm", 2283, 4000)
                    val wide = PrintAttributes.MediaSize("thermal_80", "80 mm", 3150, 4000)
                    val capabilities = PrinterCapabilitiesInfo.Builder(id)
                        .addMediaSize(if (defaultWide) wide else narrow, true)
                        .addMediaSize(if (defaultWide) narrow else wide, false)
                        .addResolution(PrintAttributes.Resolution("thermal203", "203 dpi", 203, 203), true)
                        .setColorModes(PrintAttributes.COLOR_MODE_MONOCHROME, PrintAttributes.COLOR_MODE_MONOCHROME)
                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                        .build()
                    PrinterInfo.Builder(id, device.name ?: "Bluetooth thermal printer", PrinterInfo.STATUS_IDLE)
                        .setCapabilities(capabilities)
                        .build()
                }
            } catch (_: SecurityException) {
                emptyList()
            }
        }

        private fun isLikelyPrinter(device: BluetoothDevice): Boolean {
            val name = try { device.name?.lowercase().orEmpty() } catch (_: SecurityException) { "" }
            return listOf("printer", "xprinter", "xp-", "thermal", "pos", "p323", "receipt", "58mm", "80mm")
                .any { name.contains(it) }
        }
    }

    companion object {
        private const val LEFT_MARGIN = 8
        private const val THRESHOLD = 170
        private const val MAX_PAGE_HEIGHT = 12000
    }
}
