package app.serdabvpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** The phone restarted: if the door was open before, open it again. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != "android.intent.action.QUICKBOOT_POWERON") return
        val pending = goAsync()
        Engine.restore(context.applicationContext, force = false) { pending.finish() }
    }
}
