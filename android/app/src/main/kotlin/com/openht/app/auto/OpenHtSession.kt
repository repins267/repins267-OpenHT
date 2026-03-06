package com.openht.app.auto

import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

class OpenHtSession : Session() {

    override fun onCreateScreen(intent: android.content.Intent): Screen {
        return MainCarScreen(carContext)
    }
}
