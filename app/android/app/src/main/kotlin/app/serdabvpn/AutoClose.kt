package app.serdabvpn

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.text.DateFormat
import java.util.Date

/**
 * The door closes by itself [AutoClose.schedule]d minutes after it opened:
 * a warning five minutes before, with "+1 hour", then the close. Alarms, not a
 * timer in the app, so it happens with the app swiped away and the phone asleep.
 * Inexact alarms (no exact-alarm permission): Android may fire them a few
 * minutes late, never early.
 */
object AutoClose {
    private const val PREFS = "serdab"
    private const val CLOSE_AT = "closeAt"
    private const val CHANNEL = "serdab-autoclose"
    private const val NOTE_ID = 0x5E4D
    const val WARN = "app.serdabvpn.autoclose.WARN"
    const val CLOSE = "app.serdabvpn.autoclose.CLOSE"
    const val EXTEND = "app.serdabvpn.autoclose.EXTEND"
    private const val WARN_BEFORE_MS = 5 * 60_000L

    fun closeAt(ctx: Context): Long =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong(CLOSE_AT, 0L)

    fun schedule(ctx: Context, minutes: Int) = arm(ctx, System.currentTimeMillis() + minutes * 60_000L)

    fun extend(ctx: Context, minutes: Int) {
        val base = maxOf(System.currentTimeMillis(), closeAt(ctx).takeIf { it > 0 } ?: System.currentTimeMillis())
        arm(ctx, base + minutes * 60_000L)
    }

    fun cancel(ctx: Context) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(CLOSE_AT).apply()
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.cancel(pending(ctx, WARN)); am.cancel(pending(ctx, CLOSE))
        ctx.getSystemService(NotificationManager::class.java).cancel(NOTE_ID)
    }

    private fun arm(ctx: Context, at: Long) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong(CLOSE_AT, at).apply()
        val am = ctx.getSystemService(AlarmManager::class.java)
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at - WARN_BEFORE_MS, pending(ctx, WARN))
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(ctx, CLOSE))
        ctx.getSystemService(NotificationManager::class.java).cancel(NOTE_ID)
    }

    private fun pending(ctx: Context, action: String): PendingIntent =
        PendingIntent.getBroadcast(ctx, action.hashCode(), Intent(ctx, AutoCloseReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun onAlarm(ctx: Context, action: String?) {
        val at = closeAt(ctx)
        when (action) {
            EXTEND -> extend(ctx, 60).also { Log.i("serdab", "auto-close extended to ${Date(closeAt(ctx))}") }
            WARN -> if (at > 0 && Engine.state(ctx) == "connected") warn(ctx, at)
            CLOSE -> {
                if (at == 0L) return
                if (System.currentTimeMillis() < at - 30_000) return   // extended since this alarm was set
                cancel(ctx)
                Engine.setWanted(ctx, false)
                if (Engine.state(ctx) == "connected") {
                    Engine.down(ctx)
                    note(ctx, Texts.of(ctx).closedTitle, Texts.of(ctx).closedBody, withExtend = false)
                }
            }
        }
    }

    private fun warn(ctx: Context, at: Long) {
        val t = Texts.of(ctx)
        note(ctx, t.warnTitle, t.warnBody(DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(at))), withExtend = true)
    }

    private fun note(ctx: Context, title: String, body: String, withExtend: Boolean) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, Texts.of(ctx).channel, NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val b = (if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(ctx, CHANNEL) else android.app.Notification.Builder(ctx))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
        if (withExtend) {
            b.addAction(android.app.Notification.Action.Builder(null, Texts.of(ctx).extend, pending(ctx, EXTEND)).build())
        }
        try { nm.notify(NOTE_ID, b.build()) } catch (e: SecurityException) { Log.i("serdab", "no notification permission") }
    }
}

class AutoCloseReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        AutoClose.onAlarm(ctx.applicationContext, intent.action)
    }
}

/** The few words the native side shows, in the phone's language (en, fr, ar). */
class Texts private constructor(private val lang: String) {
    private fun t(en: String, fr: String, ar: String) = when (lang) { "fr" -> fr; "ar" -> ar; else -> en }
    val channel get() = t("Closing the tunnel", "Fermeture du tunnel", "إغلاق السرداب")
    val warnTitle get() = t("Serdab closes in 5 minutes", "Serdab se ferme dans 5 minutes", "سيُغلق سرداب خلال 5 دقائق")
    fun warnBody(time: String) = t("At $time. Still on a call? Add an hour.", "À $time. Toujours en appel ? Ajoutez une heure.", "عند $time. ما زلت في مكالمة؟ أضف ساعة.")
    val extend get() = t("+1 hour", "+1 heure", "+ساعة")
    val closedTitle get() = t("Serdab closed", "Serdab est fermé", "أُغلق سرداب")
    val closedBody get() = t("Open the app when you need it again.", "Ouvrez l'app quand vous en avez besoin.", "افتح التطبيق عندما تحتاجه مجددًا.")

    companion object {
        fun of(ctx: Context) = Texts(ctx.resources.configuration.locales[0].language)
    }
}
