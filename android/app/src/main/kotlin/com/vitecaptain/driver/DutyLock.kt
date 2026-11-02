package com.vitecaptain.driver

import android.content.Context
import android.os.PowerManager

/// Keeps ride polling alive while the driver is on duty, without a status notification.
object DutyLock {
    private var lock: PowerManager.WakeLock? = null

    fun acquire(context: Context) {
        if (lock?.isHeld == true) return
        val power = context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val next = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "vitevikle:on_duty")
        next.setReferenceCounted(false)
        next.acquire()
        lock = next
    }

    fun release() {
        val current = lock
        if (current != null && current.isHeld) current.release()
        lock = null
    }
}
