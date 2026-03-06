package com.openht.app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

class WxScreen(carContext: CarContext) : Screen(carContext) {

    private val wxChannels = listOf(
        Triple("WX1", 162.400, "162.400 MHz"),
        Triple("WX2", 162.425, "162.425 MHz"),
        Triple("WX3", 162.450, "162.450 MHz"),
        Triple("WX4", 162.475, "162.475 MHz"),
        Triple("WX5", 162.500, "162.500 MHz"),
        Triple("WX6", 162.525, "162.525 MHz"),
        Triple("WX7", 162.550, "162.550 MHz"),
    )

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()

        for ((label, _, freqStr) in wxChannels) {
            listBuilder.addItem(
                Row.Builder()
                    .setTitle(label)
                    .addText(freqStr)
                    // TODO: trigger tune via shared state / intent
                    .build()
            )
        }

        return ListTemplate.Builder()
            .setSingleList(listBuilder.build())
            .setTitle("NOAA Weather Radio")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
