package com.openht.app.auto

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template

class RepeaterListScreen(carContext: CarContext) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        // Placeholder — will be wired to RepeaterBookConnectService in a future pass
        val listBuilder = ItemList.Builder()
            .setNoItemsMessage("No repeaters loaded. Open OpenHT on your phone first.")

        // TODO: query RepeaterBook CP via Binder/IPC or cache and populate rows here

        return ListTemplate.Builder()
            .setSingleList(listBuilder.build())
            .setTitle("Near Repeaters")
            .setHeaderAction(Action.BACK)
            .build()
    }
}
