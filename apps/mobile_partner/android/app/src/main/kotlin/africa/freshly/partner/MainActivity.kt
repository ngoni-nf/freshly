package africa.freshly.partner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createFreshlyNotificationChannels(this)
    }
}

/**
 * Creates the two channels the API sends on, at high importance, before any
 * push can arrive.
 *
 * Without this, FCM creates an unknown channel itself at default importance:
 * the notification is delivered but silent, with no heads-up banner. For a job
 * offer with a sixty-second window, that is the difference between seeing it
 * and missing it. Ids must match `channelId` in the API's push calls.
 *
 * Android never raises a channel's importance after it exists. A device that
 * already received a push on a default-importance channel keeps it until the
 * app is reinstalled or its data cleared, so test on a fresh install.
 */
internal fun createFreshlyNotificationChannels(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    manager.createNotificationChannels(
        listOf(
            NotificationChannel(
                "freshly_dispatch",
                "Job offers and messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "New requests and messages that need an answer quickly"
            },
            NotificationChannel(
                "freshly_bookings",
                "Booking updates",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Arrivals, status changes and booking messages"
            },
        ),
    )
}
