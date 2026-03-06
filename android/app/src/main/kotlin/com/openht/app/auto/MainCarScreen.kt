package com.openht.app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat

class MainCarScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()

        listBuilder.addItem(
            Row.Builder()
                .setTitle("Near Repeaters")
                .addText("Tap to browse nearby repeaters")
                .setOnClickListener {
                    screenManager.push(RepeaterListScreen(carContext))
                }
                .build()
        )

        listBuilder.addItem(
            Row.Builder()
                .setTitle("NOAA Weather")
                .addText("WX1–WX7 and active alerts")
                .setOnClickListener {
                    screenManager.push(WxScreen(carContext))
                }
                .build()
        )

        listBuilder.addItem(
            Row.Builder()
                .setTitle("Radio Status")
                .addText("Connection and frequency info")
                .setOnClickListener {
                    screenManager.push(RadioStatusScreen(carContext))
                }
                .build()
        )

        return ListTemplate.Builder()
            .setSingleList(listBuilder.build())
            .setTitle("OpenHT")
            .setHeaderAction(Action.APP_ICON)
            .build()
    }
}
