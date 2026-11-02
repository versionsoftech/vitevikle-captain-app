package com.vitecaptain.driver

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.MapsInitializer
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.Polyline
import com.google.android.gms.maps.model.PolylineOptions
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class RideBubbleService : Service() {
    private var windowManager: WindowManager? = null
    private var bubble: View? = null
    private var mapView: MapView? = null
    private var googleMap: GoogleMap? = null
    private var addressView: TextView? = null
    private var timeView: TextView? = null
    private var driverMarker: Marker? = null
    private var targetMarker: Marker? = null
    private var routeLine: Polyline? = null
    private var driverPoint: LatLng? = null
    private var targetPoint: LatLng? = null
    private var dotIcon: BitmapDescriptor? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Ride in progress"
        val body = intent?.getStringExtra("body") ?: ""
        startForeground(ONGOING_ID, buildNotification(title, body))
        if (intent == null || MainActivity.appInForeground || dismissedByUser || !Settings.canDrawOverlays(this)) {
            finishQuietly()
            return START_NOT_STICKY
        }
        rememberPoints(intent)
        if (intent.action == "move" && bubble != null) {
            addressView?.text = body.ifBlank { "Follow the route" }
            timeView?.text = clock()
            drawMap()
            return START_STICKY
        }
        showBubble(body)
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    private fun rememberPoints(intent: Intent) {
        val lat = intent.getDoubleExtra("lat", 0.0)
        val lng = intent.getDoubleExtra("lng", 0.0)
        val targetLat = intent.getDoubleExtra("targetLat", 0.0)
        val targetLng = intent.getDoubleExtra("targetLng", 0.0)
        if (lat != 0.0 || lng != 0.0) driverPoint = LatLng(lat, lng)
        if (targetLat != 0.0 || targetLng != 0.0) targetPoint = LatLng(targetLat, targetLng)
    }

    private fun showBubble(address: String) {
        if (bubble != null) {
            addressView?.text = address.ifBlank { "Follow the route" }
            timeView?.text = clock()
            drawMap()
            return
        }
        try {
            MapsInitializer.initialize(applicationContext)
        } catch (_: Exception) {
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        val themed = ContextThemeWrapper(this, android.R.style.Theme_DeviceDefault)

        val card = FrameLayout(themed).apply {
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(Color.parseColor("#102033"))
            }
            outlineProvider = ViewOutlineProvider.BACKGROUND
            clipToOutline = true
            elevation = dp(10).toFloat()
        }

        val map = try {
            MapView(themed).also {
                it.onCreate(null)
                it.onStart()
            }
        } catch (_: Exception) {
            null
        }
        if (map != null) {
            map.getMapAsync { ready ->
                if (mapView == null) return@getMapAsync
                googleMap = ready
                ready.uiSettings.apply {
                    isMapToolbarEnabled = false
                    isZoomControlsEnabled = false
                    isCompassEnabled = false
                    isMyLocationButtonEnabled = false
                    setAllGesturesEnabled(false)
                }
                try {
                    ready.setMapStyle(MapStyleOptions(NIGHT_STYLE))
                } catch (_: Exception) {
                }
                drawMap()
            }
            card.addView(map, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ))
            mapView = map
        }

        val caption = android.widget.LinearLayout(themed).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(dp(10), dp(6), dp(10), dp(8))
            setBackgroundColor(Color.parseColor("#CC0E1A2B"))
        }
        val place = TextView(themed).apply {
            text = address.ifBlank { "Follow the route" }
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        val time = TextView(themed).apply {
            text = clock()
            setTextColor(Color.parseColor("#D6DEE8"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            maxLines = 1
        }
        caption.addView(place)
        caption.addView(time)
        card.addView(caption, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        ))
        addressView = place
        timeView = time

        val shield = View(themed)
        card.addView(shield, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))

        val close = TextView(themed).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#CC1B2838"))
            }
            setOnClickListener { closeByUser() }
        }
        card.addView(close, FrameLayout.LayoutParams(dp(26), dp(26), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(6)
            marginEnd = dp(6)
        })

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            dp(176),
            dp(168),
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            x = dp(12)
            y = dp(24)
        }
        attachDrag(wm, shield, card, params)
        wm.addView(card, params)
        map?.onResume()
        bubble = card
    }

    private fun drawMap() {
        val map = googleMap ?: return
        val here = driverPoint
        val goal = targetPoint
        if (here == null && goal == null) return
        if (dotIcon == null) dotIcon = blueDot()
        if (here != null) {
            val marker = driverMarker
            if (marker == null) {
                driverMarker = map.addMarker(MarkerOptions().position(here).anchor(0.5f, 0.5f).icon(dotIcon).zIndex(2f))
            } else {
                marker.position = here
            }
        }
        if (goal != null) {
            val marker = targetMarker
            if (marker == null) {
                targetMarker = map.addMarker(
                    MarkerOptions().position(goal).icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE))
                )
            } else {
                marker.position = goal
            }
        }
        val line = routeLine
        if (here != null && goal != null) {
            if (line == null) {
                routeLine = map.addPolyline(
                    PolylineOptions().add(here, goal).color(Color.parseColor("#4FC3F7")).width(10f)
                )
            } else {
                line.points = listOf(here, goal)
            }
            try {
                val bounds = LatLngBounds.builder().include(here).include(goal).build()
                map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, dp(36)))
            } catch (_: Exception) {
                map.moveCamera(CameraUpdateFactory.newLatLngZoom(here, 15f))
            }
        } else {
            map.moveCamera(CameraUpdateFactory.newLatLngZoom(here ?: goal!!, 16f))
        }
    }

    private fun blueDot(): BitmapDescriptor {
        val size = dp(22)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.WHITE
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
        paint.color = Color.parseColor("#1A73E8")
        canvas.drawCircle(size / 2f, size / 2f, size / 2f - dp(3), paint)
        return BitmapDescriptorFactory.fromBitmap(bitmap)
    }

    private fun attachDrag(
        wm: WindowManager,
        shield: View,
        card: View,
        params: WindowManager.LayoutParams
    ) {
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        val screenW = resources.displayMetrics.widthPixels
        val screenH = resources.displayMetrics.heightPixels
        shield.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (kotlin.math.abs(dx) > 8 || kotlin.math.abs(dy) > 8) moved = true
                    val maxX = (screenW - params.width).coerceAtLeast(0)
                    val maxY = (screenH - params.height).coerceAtLeast(0)
                    params.x = (startX - dx).coerceIn(0, maxX)
                    params.y = (startY - dy).coerceIn(-dp(72), maxY)
                    try {
                        wm.updateViewLayout(card, params)
                    } catch (_: Exception) {
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (params.y < -dp(36)) {
                        closeByUser()
                    } else if (!moved) {
                        openApp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun closeByUser() {
        dismissedByUser = true
        finishQuietly()
    }

    private fun finishQuietly() {
        removeBubble()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
        stopSelf()
    }

    private fun removeBubble() {
        val map = mapView
        mapView = null
        googleMap = null
        driverMarker = null
        targetMarker = null
        routeLine = null
        if (map != null) {
            try {
                map.onPause()
                map.onStop()
                map.onDestroy()
            } catch (_: Exception) {
            }
        }
        val view = bubble
        bubble = null
        if (view != null) {
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
    }

    private fun openApp() {
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(open)
    }

    private fun clock(): String {
        return SimpleDateFormat("h:mm a", Locale.US).format(Date())
    }

    private fun buildNotification(title: String, body: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ongoing ride",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.description = "Shows while a ride is in progress"
            channel.setSound(null, null)
            manager.createNotificationChannel(channel)
        }
        val open = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pending = PendingIntent.getActivity(
            this,
            21,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title.ifBlank { "Ride in progress" })
            .setContentText(body.ifBlank { "Tap to return to the ride" })
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(pending)
            .build()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    class Payload(
        val title: String,
        val body: String,
        val eta: String,
        val lat: Double,
        val lng: Double,
        val targetLat: Double,
        val targetLng: Double,
    ) {
        fun toIntent(context: android.content.Context, action: String?): Intent {
            return Intent(context, RideBubbleService::class.java).apply {
                if (action != null) this.action = action
                putExtra("title", title)
                putExtra("body", body)
                putExtra("eta", eta)
                putExtra("lat", lat)
                putExtra("lng", lng)
                putExtra("targetLat", targetLat)
                putExtra("targetLng", targetLng)
            }
        }
    }

    companion object {
        private const val CHANNEL_ID = "vitevikle_ongoing_ride"
        private const val ONGOING_ID = 2402
        @Volatile var dismissedByUser = false
        @Volatile var pending: Payload? = null

        private const val NIGHT_STYLE =
            "[{\"elementType\":\"geometry\",\"stylers\":[{\"color\":\"#1d2c4d\"}]}," +
                "{\"elementType\":\"labels.text.fill\",\"stylers\":[{\"color\":\"#8ec3b9\"}]}," +
                "{\"elementType\":\"labels.text.stroke\",\"stylers\":[{\"color\":\"#1a3646\"}]}," +
                "{\"featureType\":\"road\",\"elementType\":\"geometry\",\"stylers\":[{\"color\":\"#304a7d\"}]}," +
                "{\"featureType\":\"road\",\"elementType\":\"geometry.stroke\",\"stylers\":[{\"color\":\"#1a3646\"}]}," +
                "{\"featureType\":\"water\",\"elementType\":\"geometry\",\"stylers\":[{\"color\":\"#0e1626\"}]}]"
    }
}
