package com.vitecaptain.driver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Plays the order alarm when a ride push arrives and the screen is off.
class RideRingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val extras = intent?.extras ?: return
        val blob = StringBuilder()
        for (key in extras.keySet()) {
            blob.append(key).append(' ').append(extras.get(key)).append(' ')
        }
        val text = blob.toString().lowercase()
        if (text.contains("otp")) return
        val order = text.contains("ride request") ||
            text.contains("new ride") ||
            text.contains("new order") ||
            text.contains("ride_request") ||
            text.contains("ride_requested") ||
            text.contains("new_ride") ||
            text.contains("intercity") ||
            text.contains("parcel")
        if (!order) return
        OrderRingPlayer.start(context.applicationContext)
    }
}
