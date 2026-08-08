package com.vitecaptain.driver

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.graphics.BitmapFactory
import android.widget.ImageView

class SplashActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
}
