package com.vitecaptain.driver

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.graphics.BitmapFactory
import android.widget.ImageView

class SplashActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launcher = intent?.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_LAUNCHER)
        if (launcher && (bringExistingAppForward() || !isTaskRoot)) {
            finish()
            overridePendingTransition(0, 0)
            return
        }
        setContentView(R.layout.activity_splash)

        val logoView = findViewById<ImageView>(R.id.ivSplashLogo)
        try {
            assets.open("flutter_assets/assets/images/splash_logo.png").use { input ->
                val bitmap = BitmapFactory.decodeStream(input)
                if (bitmap != null) {
                    logoView.setImageBitmap(bitmap)
                }
            }
        } catch (_: Exception) {
            // Fall back to whatever is set in XML (@drawable/splash)
        }

        logoView.post {
            startActivity(Intent(this, MainActivity::class.java))
            overridePendingTransition(0, 0)
            finish()
            overridePendingTransition(0, 0)
        }
    }

    private fun bringExistingAppForward(): Boolean {
        if (Build.VERSION.SDK_INT < 29) return false
        val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        for (task in manager.appTasks) {
            val info = task.taskInfo
            val base = info.baseActivity?.className.orEmpty()
            val top = info.topActivity?.className.orEmpty()
            if (info.taskId == taskId) continue
            if (base.contains("MainActivity") || top.contains("MainActivity")) {
                task.moveToFront()
                return true
            }
        }
        return false
    }
}
