package si.triparna.jivie

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vsakdan/remote_push_readiness")
            .setMethodCallHandler { call, result ->
                if (call.method == "applicationId") result.success(applicationContext.packageName)
                else result.notImplemented()
            }
    }
}
