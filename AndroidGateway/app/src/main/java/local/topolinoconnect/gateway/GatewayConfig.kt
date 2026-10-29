package local.topolinoconnect.gateway

import android.content.Context

/** Minimal local preference used only for optional BLE startup after reboot. */
object GatewayConfig {
    enum class InputMode { NONE, BLUETOOTH, USB_OTG }

    fun setInputMode(context: Context, mode: InputMode) {
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putString(INPUT_MODE, mode.name).apply()
    }

    fun inputMode(context: Context): InputMode = runCatching {
        InputMode.valueOf(context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getString(INPUT_MODE, InputMode.NONE.name) ?: InputMode.NONE.name)
    }.getOrDefault(InputMode.NONE)

    fun setAutoStart(context: Context, enabled: Boolean) {
        context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit().putBoolean(AUTO_START, enabled).apply()
    }

    fun shouldAutoStart(context: Context): Boolean = context.applicationContext
        .getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        .getBoolean(AUTO_START, false)

    private const val PREFERENCES = "topolino_monitor"
    private const val AUTO_START = "start_after_reboot"
    private const val INPUT_MODE = "input_mode"
}
