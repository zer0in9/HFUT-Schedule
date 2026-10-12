package com.hfut.schedule.shared.ui

import androidx.compose.runtime.*
import androidx.compose.ui.window.ComposeUIViewController
import com.hfut.schedule.shared.ScheduleRepository
import com.hfut.schedule.shared.ScheduleStorage
import com.hfut.schedule.shared.currentLocalDate
import kotlinx.coroutines.delay
import platform.Foundation.NSURL
import platform.Foundation.NSUserDefaults
import platform.UIKit.UIApplication

private class IOSScheduleStorage : ScheduleStorage {
    private val defaults = NSUserDefaults.standardUserDefaults
    private val key = "hfut.schedule.v1"
    override fun read(): String? = defaults.stringForKey(key)
    override fun write(value: String) = defaults.setObject(value, forKey = key)
}

fun MainViewController() = ComposeUIViewController {
    val repository = remember { ScheduleRepository(IOSScheduleStorage()) }
    var today by remember { mutableStateOf(currentLocalDate()) }
    LaunchedEffect(Unit) {
        while (true) {
            today = currentLocalDate()
            delay(60_000)
        }
    }
    ScheduleApp(repository, today) { address ->
        NSURL.URLWithString(address)?.let { UIApplication.sharedApplication.openURL(it, options = emptyMap<Any?, Any>(), completionHandler = null) }
    }
}
