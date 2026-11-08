package app.serdabvpn

import android.content.Context
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/**
 * The one WireGuard backend of the process, shared by the Flutter channel, the
 * boot receiver and Android's Always-on callback. The backend remembers which
 * Tunnel object is up by identity, so there must be exactly one of each.
 */
object Engine {
    private const val TAG = "serdab"
    private const val PREFS = "serdab"
    private const val WANTED = "wanted" // the person wants the door open: bring it back after a reboot

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val listeners = CopyOnWriteArraySet<(String) -> Unit>()
    @Volatile private var backend: GoBackend? = null
    @Volatile var phase: String? = null // "connecting" / "disconnecting" while the backend works
        private set

    val tunnel = object : Tunnel {
        override fun getName() = "serdab"
        override fun onStateChange(newState: Tunnel.State) {
            phase = null
            emit(if (newState == Tunnel.State.UP) "connected" else "disconnected")
        }
    }

    fun backend(context: Context): GoBackend =
        backend ?: synchronized(this) { backend ?: GoBackend(context.applicationContext).also { backend = it } }

    fun state(context: Context): String =
        phase ?: if (backend(context).getState(tunnel) == Tunnel.State.UP) "connected" else "disconnected"

    fun listen(l: (String) -> Unit) { listeners.add(l) }
    fun unlisten(l: (String) -> Unit) { listeners.remove(l) }

    private fun emit(state: String) {
        main.post { listeners.forEach { it(state) } }
    }

    fun wanted(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(WANTED, false)

    fun setWanted(context: Context, v: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(WANTED, v).apply()
    }

    /** Runs [block] on the engine's thread, then [done] on the main thread with the error if any. */
    fun up(context: Context, config: Config, done: (Throwable?) -> Unit = {}) {
        phase = "connecting"; emit("connecting")
        worker.execute {
            val err = try { backend(context).setState(tunnel, Tunnel.State.UP, config); null } catch (e: Throwable) { e }
            if (err != null) { phase = null; emit(state(context)); Log.w(TAG, "up failed", err) }
            main.post { done(err) }
        }
    }

    fun down(context: Context, done: (Throwable?) -> Unit = {}) {
        phase = "disconnecting"; emit("disconnecting")
        worker.execute {
            val err = try { backend(context).setState(tunnel, Tunnel.State.DOWN, null); null } catch (e: Throwable) { e }
            if (err != null) { phase = null; emit(state(context)); Log.w(TAG, "down failed", err) }
            main.post { done(err) }
        }
    }

    /**
     * Brings the saved tunnel back without any UI: after a boot (only if the
     * person wanted it open) or when Android's Always-on VPN asks ([force]).
     * Needs the VPN consent the person already gave; without it, nothing happens.
     */
    fun restore(context: Context, force: Boolean, done: (Boolean) -> Unit = {}) {
        if (!force && !wanted(context)) { done(false); return }
        if (VpnService.prepare(context) != null) { Log.i(TAG, "restore: no VPN consent yet"); done(false); return }
        val text = Vault.load(context) ?: run { done(false); return }
        val config = try { Config.parse(text.byteInputStream()) } catch (e: Exception) { Log.w(TAG, "restore: bad saved config", e); done(false); return }
        if (backend(context).getState(tunnel) == Tunnel.State.UP) { done(true); return }
        up(context, config) { done(it == null) }
    }
}
