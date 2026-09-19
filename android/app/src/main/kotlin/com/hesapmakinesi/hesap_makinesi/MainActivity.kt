package com.hesapmakinesi.hesap_makinesi

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

open class MainActivity : FlutterActivity() {
    private val channelName = "com.hesapmakinesi.hesap_makinesi/launcher_icon"
    private val screenSecurityChannelName =
        "com.hesapmakinesi.hesap_makinesi/screen_security"
    private val videoConcatChannelName =
        "com.hesapmakinesi.hesap_makinesi/video_concat"
    private val nudgeChannelName = "com.hesapmakinesi.hesap_makinesi/nudge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setLauncherIcon") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val samsung = call.argument<Boolean>("samsung") == true
            val enabled = if (samsung) "SamsungLauncherAlias" else "ClassicLauncherAlias"
            val disabled = if (samsung) "ClassicLauncherAlias" else "SamsungLauncherAlias"
            try {
                val samsungOn = isLauncherEnabled("SamsungLauncherAlias", true)
                val classicOn = isLauncherEnabled("ClassicLauncherAlias", false)
                if ((samsung && samsungOn && !classicOn) ||
                    (!samsung && classicOn && !samsungOn)
                ) {
                    result.success(enabled)
                    return@setMethodCallHandler
                }

                val enabledComponent = ComponentName(this, "$packageName.$enabled")
                val disabledComponent = ComponentName(this, "$packageName.$disabled")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.setComponentEnabledSettings(
                        listOf(
                            PackageManager.ComponentEnabledSetting(
                                enabledComponent,
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                PackageManager.DONT_KILL_APP,
                            ),
                            PackageManager.ComponentEnabledSetting(
                                disabledComponent,
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP,
                            ),
                        ),
                    )
                } else {
                    packageManager.setComponentEnabledSetting(
                        enabledComponent,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                    packageManager.setComponentEnabledSetting(
                        disabledComponent,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }

                Log.i("LauncherIcon", "Active alias: $enabled")
                result.success(enabled)
            } catch (error: Exception) {
                Log.e("LauncherIcon", "Could not activate $enabled", error)
                result.error("ICON_CHANGE_FAILED", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            screenSecurityChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setScreenProtection") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val enabled = call.argument<Boolean>("enabled") == true
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            result.success(enabled)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            nudgeChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    NudgeVibration.play(this)
                    result.success(null)
                }
                "batteryUnrestricted" -> {
                    result.success(NudgeVibration.isBatteryUnrestricted(this))
                }
                "requestBatteryUnrestricted" -> {
                    NudgeVibration.requestBatteryUnrestricted(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            videoConcatChannelName,
        ).setMethodCallHandler { call, result ->
            if (call.method != "concat") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val inputs = call.argument<List<String>>("inputs").orEmpty()
            val output = call.argument<String>("output").orEmpty()
            if (inputs.size < 2 || output.isEmpty()) {
                result.error("BAD_ARGS", "Birleştirilecek video parçası yok.", null)
                return@setMethodCallHandler
            }
            try {
                VideoConcat.concat(inputs, output)
                result.success(output)
            } catch (error: Exception) {
                Log.e("VideoConcat", "Could not concat videos", error)
                result.error("CONCAT_FAILED", error.message, null)
            }
        }
    }

    private fun isLauncherEnabled(name: String, enabledByDefault: Boolean): Boolean {
        val state = packageManager.getComponentEnabledSetting(
            ComponentName(this, "$packageName.$name"),
        )
        return when (state) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            else -> enabledByDefault
        }
    }
}

class SamsungLauncherAlias : MainActivity()

class ClassicLauncherAlias : MainActivity()
