package app.serdabvpn

import android.app.Application
import com.wireguard.android.backend.GoBackend

class SerdabApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Settings > VPN > Serdab > "Always-on VPN": Android starts our VpnService
        // with no intent and the backend tells us; we answer with the saved config.
        GoBackend.setAlwaysOnCallback { Engine.restore(this, force = true) }
    }
}
