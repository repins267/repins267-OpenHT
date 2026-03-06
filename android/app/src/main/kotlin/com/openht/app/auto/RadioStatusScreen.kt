package com.openht.app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

class RadioStatusScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val row = Row.Builder()
            .setTitle("Radio Status")
            .addText("Open OpenHT on your phone to connect and control the radio.")
            .build()

        return PaneTemplate.Builder(
            Pane.Builder().addRow(row).build()
        )
            .setTitle("Radio")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
