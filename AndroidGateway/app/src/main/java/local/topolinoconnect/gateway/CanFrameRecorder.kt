package local.topolinoconnect.gateway

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

/** Writes raw CAN frames off the Bluetooth callback thread as newline-delimited JSON. */
object CanFrameRecorder {
    private val writer = Executors.newSingleThreadExecutor { task ->
        Thread(task, "topolino-can-log").apply { isDaemon = true }
    }
    private val formatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss'Z'").withZone(ZoneOffset.UTC)
    @Volatile private var activeFile: File? = null

    fun record(context: Context, frame: JSONObject) {
        val snapshot = JSONObject(frame.toString())
        writer.execute {
            runCatching {
                val destination = activeFile ?: File(
                    File(context.applicationContext.filesDir, "captures"),
                    "esp-can-${formatter.format(Instant.now())}.jsonl"
                ).also {
                    it.parentFile?.mkdirs()
                    activeFile = it
                    GatewayRuntime.canFrameLogPath = it.absolutePath
                }
                destination.appendText(snapshot.toString() + "\n", Charsets.UTF_8)
            }
        }
    }
}
