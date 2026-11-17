package com.goride.rider

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createUpdatesChannel()
    }

    /** Canal de los avisos del viaje (conductor en camino, llegó, finalizado, mensajes). */
    private fun createUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            "goride_rider_updates",
            "Avisos del viaje",
            NotificationManager.IMPORTANCE_HIGH
        )
        channel.description = "Conductor en camino, llegada, viaje finalizado y mensajes"
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
