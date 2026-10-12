package com.hfut.schedule.shared.ui

import androidx.compose.runtime.*
import androidx.compose.ui.window.ComposeUIViewController
import com.hfut.schedule.shared.ScheduleRepository
import com.hfut.schedule.shared.ScheduleStorage
import kotlinx.coroutines.delay
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn
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
    var today by remember { mutableStateOf(Clock.System.todayIn(TimeZone.currentSystemDefault())) }
    LaunchedEffect(Unit) {
        while (true) {
            today = Clock.System.todayIn(TimeZone.currentSystemDefault())
            delay(60_000)
        }
    }
    ScheduleApp(repository, today) { address ->
        NSURL.URLWithString(address)?.let { UIApplication.sharedApplication.openURL(it, options = emptyMap<Any?, Any>(), completionHandler = null) }
    }
}
