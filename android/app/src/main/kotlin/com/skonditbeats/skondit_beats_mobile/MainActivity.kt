package com.skonditbeats.skondit_beats_mobile

import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth necesita FragmentActivity para mostrar el diálogo biométrico, y
// audio_service necesita esta variante para compartir el motor de Flutter.
class MainActivity : AudioServiceFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pantalla segura: bloquea capturas y grabación en pago y OTP.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.skonditbeats/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "disable" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
