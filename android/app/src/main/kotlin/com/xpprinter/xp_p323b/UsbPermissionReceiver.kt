package com.xpprinter.xp_p323b

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbManager

class UsbPermissionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val relay = Intent(context.packageName + ".USB_PERMISSION_RESULT")
            .setPackage(context.packageName)
            .putExtra(
                UsbManager.EXTRA_PERMISSION_GRANTED,
                intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false),
            )
        context.sendBroadcast(relay)
    }
}
