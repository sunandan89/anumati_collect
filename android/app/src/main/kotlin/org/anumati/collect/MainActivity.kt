package org.anumati.collect

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Screens show names, phone numbers and consent evidence: block screenshots,
        // screen recording and the recent-apps preview. Set before super.onCreate, so the
        // window is secure before Flutter creates its drawing surface: changing it on a live
        // surface left some phones with a black screen when the app came back after a while.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }
}
