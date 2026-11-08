package app.serdabvpn

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.provider.Settings
import com.wireguard.config.BadConfigException
import com.wireguard.config.Config
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * The Android half of the `serdab/tunnel` channel, a thin door over [Engine].
 */
class TunnelChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private var events: EventChannel.EventSink? = null
    private var pendingPrepare: MethodChannel.Result? = null
    private val listener: (String) -> Unit = { events?.success(it) }

    init {
        Engine.listen(listener)
        MethodChannel(messenger, "serdab/tunnel").setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> prepare(result)
                "connect" -> connect(call.argument<String>("config"), call.argument<Boolean>("alwaysOn") ?: true, result)
                "disconnect" -> {
                    Engine.setWanted(activity, false)
                    Engine.down(activity) { finish(it, result) }
                }
                "setAlwaysOn" -> { Engine.setWanted(activity, call.argument<Boolean>("enabled") ?: true); result.success(null) }
                "openVpnSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "state" -> result.success(Engine.state(activity))
                "stats" -> stats(result)
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "serdab/tunnel/state").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                events = sink
                sink.success(Engine.state(activity))
            }

            override fun onCancel(args: Any?) {
                events = null
            }
        })
    }

    fun dispose() {
        Engine.unlisten(listener)
    }

    /** Android asks once, system dialog, before any app may open a VpnService. */
    private fun prepare(result: MethodChannel.Result) {
        val intent = VpnService.prepare(activity)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPrepare = result
        activity.startActivityForResult(intent, REQUEST_VPN)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        val ok = resultCode == Activity.RESULT_OK
        pendingPrepare?.success(ok)
        pendingPrepare = null
        if (!ok) events?.success("denied")
        return true
    }

    private fun connect(config: String?, alwaysOn: Boolean, result: MethodChannel.Result) {
        if (config == null) {
            result.error("bad_config", "no config", null)
            return
        }
        val parsed = try {
            Config.parse(config.byteInputStream())
        } catch (e: BadConfigException) {
            val where = listOf(e.section.name, e.location.name).joinToString(" ") { it.lowercase().replace('_', ' ') }.trim()
            val what = e.reason.name.lowercase().replace('_', ' ')
            result.error("bad_config", "$where: $what ${e.text ?: ""}".trim(), null)
            return
        } catch (e: Exception) {
            result.error("bad_config", e.message ?: e.toString(), null)
            return
        }
        Vault.save(activity, config)
        Engine.setWanted(activity, alwaysOn)
        Engine.up(activity, parsed) { finish(it, result) }
    }

    private fun finish(err: Throwable?, result: MethodChannel.Result) {
        if (err == null) result.success(null) else result.error("tunnel", err.message ?: err.toString(), null)
    }

    private fun stats(result: MethodChannel.Result) {
        Thread {
            val s = try { Engine.backend(activity).getStatistics(Engine.tunnel) } catch (e: Exception) { null }
            val map = s?.let { stats ->
                val handshake = stats.peers().maxOfOrNull { stats.peer(it)?.latestHandshakeEpochMillis() ?: 0L } ?: 0L
                mapOf("rxBytes" to stats.totalRx(), "txBytes" to stats.totalTx(), "lastHandshake" to handshake / 1000)
            }
            activity.runOnUiThread { result.success(map) }
        }.start()
    }

    companion object {
        const val REQUEST_VPN = 0x5E4D
    }
}
