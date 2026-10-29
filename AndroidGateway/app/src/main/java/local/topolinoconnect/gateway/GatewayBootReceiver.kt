package local.topolinoconnect.gateway

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class GatewayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) return
        if (!GatewayConfig.shouldAutoStart(context)) return

        val service = Intent(context, GatewayService::class.java).setAction(GatewayService.ACTION_START)
        runCatching {
            context.startForegroundService(service)
        }.onFailure {
            GatewayRuntime.status = "Android yeniden başlarken otomatik başlatamadı; uygulamayı açıp tekrar başlat"
        }
    }
}
