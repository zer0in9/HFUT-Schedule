package com.hfut.schedule.shared.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.hfut.schedule.shared.*
import com.xah.common.logic.model.Campus
import kotlinx.datetime.LocalDate

private val dayNames = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")

@Composable
fun ScheduleApp(repository: ScheduleRepository, today: LocalDate, openUrl: (String) -> Unit) {
    val loaded = remember(repository) { runCatching { repository.load(today) } }
    var schedule by remember { mutableStateOf(loaded.getOrElse { Schedule.empty(today) }) }
    var loadFailed by remember { mutableStateOf(loaded.isFailure) }
    var error by remember { mutableStateOf(loaded.exceptionOrNull()?.let { "读取课表失败，原始数据已保留：${it.message}" }) }
    var week by rememberSaveable { mutableStateOf(schedule.weekOn(today).coerceIn(1, MAX_WEEKS)) }
    var day by rememberSaveable { mutableStateOf(today.dayOfWeek.ordinal + 1) }
    var page by rememberSaveable { mutableStateOf(0) }
    var editor by remember { mutableStateOf<Course?>(null) }
    var adding by remember { mutableStateOf(false) }
    var resetting by remember { mutableStateOf(false) }

    fun save(next: Schedule): Boolean = try {
        check(!loadFailed) { "请先在设置中重置无法读取的课表" }
        repository.save(next)
        schedule = next
        true
    } catch (e: Exception) {
        error = "保存失败：${e.message}"
        false
    }

    MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
        Scaffold(
            bottomBar = {
                NavigationBar {
                    listOf("课表", "校园", "设置").forEachIndexed { index, title ->
                        NavigationBarItem(
                            selected = page == index, onClick = { page = index },
                            icon = { Text(listOf("课", "校", "设")[index]) }, label = { Text(title) }
                        )
                    }
                }
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding)
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal))) {
                Text("聚在工大", style = MaterialTheme.typography.headlineMedium, modifier = Modifier.padding(16.dp))
                when (page) {
                    0 -> {
                        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            TextButton(onClick = { week-- }, enabled = week > 1) { Text("上一周") }
                            TextButton(onClick = { week = schedule.weekOn(today).coerceIn(1, MAX_WEEKS) }) { Text("第 $week 周 · 回本周") }
                            TextButton(onClick = { week++ }, enabled = week < MAX_WEEKS) { Text("下一周") }
                        }
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${schedule.dateAt(week, 1)} 起", modifier = Modifier.weight(1f))
                            FilledTonalButton(onClick = { adding = true }, enabled = !loadFailed) { Text("添加课程") }
                        }
                        if (schedule.courses.isEmpty()) {
                            Text("暂无课程。先在设置中填写开学日期，再添加课程。", Modifier.padding(16.dp))
                        }
                        if (loadFailed) Text("课表读取失败，请前往设置处理。", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error)
                        BoxWithConstraints(Modifier.fillMaxSize()) {
                            // Respond to window width, including iPad split view and Stage Manager.
                            if (maxWidth >= 840.dp) {
                                Row(Modifier.fillMaxSize().padding(8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    (1..7).forEach { weekday ->
                                        DayColumn(schedule, week, weekday, { editor = it }, Modifier.weight(1f))
                                    }
                                }
                            } else {
                                Column {
                                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 12.dp),
                                        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        dayNames.forEachIndexed { index, label ->
                                            FilterChip(selected = day == index + 1, onClick = { day = index + 1 }, label = { Text(label) })
                                        }
                                    }
                                    DayColumn(schedule, week, day, { editor = it }, Modifier.fillMaxSize().padding(16.dp))
                                }
                            }
                        }
                    }
                    1 -> Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("校园服务", style = MaterialTheme.typography.titleLarge)
                        Text("在浏览器中访问学校服务。登录状态不会自动同步到课表。")
                        listOf(
                            "信息门户" to "https://one.hfut.edu.cn/",
                            "合工大教务" to "https://jwglapp.hfut.edu.cn/uniapp/",
                            "WebVPN" to "https://webvpn.hfut.edu.cn/",
                            "图书馆" to "https://lib.hfut.edu.cn/",
                            "学校新闻" to "https://news.hfut.edu.cn/",
                        ).forEach { (name, url) ->
                            OutlinedButton(onClick = { openUrl(url) }, modifier = Modifier.fillMaxWidth()) { Text(name) }
                        }
                        Text("校区：${Campus.entries.joinToString(" · ") { it.description }}")
                    }
                    else -> {
                        var start by remember(schedule.semesterStart) { mutableStateOf(schedule.semesterStart) }
                        var saved by remember { mutableStateOf(false) }
                        Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text("学期设置", style = MaterialTheme.typography.titleLarge)
                            OutlinedTextField(value = start, onValueChange = { start = it; saved = false },
                                label = { Text("第一周周一（YYYY-MM-DD）") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            Button(onClick = {
                                if (save(schedule.copy(semesterStart = start.trim()))) {
                                    week = schedule.weekOn(today).coerceIn(1, MAX_WEEKS)
                                    saved = true
                                }
                            }, enabled = !loadFailed) { Text(if (saved) "已保存" else "保存学期") }
                            Text("iOS 首版支持离线课程管理和校园网站入口；统一认证、自动同步课表、成绩和校园卡正在逐步迁移。")
                            Text("课程保存在本机，卸载应用将删除数据。当前未提供 Android 备份导入。")
                            OutlinedButton(onClick = { resetting = true }) { Text("重置本机课表") }
                        }
                    }
                }
            }
        }
        if (adding || editor != null) {
            CourseEditor(editor, day, onDismiss = { adding = false; editor = null }, onSave = { course ->
                val next = schedule.copy(courses = schedule.courses.filterNot { it.id == course.id } + course)
                if (save(next)) { adding = false; editor = null }
            }, onDelete = { course ->
                if (save(schedule.copy(courses = schedule.courses.filterNot { it.id == course.id }))) editor = null
            })
        }
        if (error != null) AlertDialog(onDismissRequest = { error = null }, title = { Text("课表提示") },
            text = { Text(error.orEmpty()) }, confirmButton = { TextButton(onClick = { error = null }) { Text("知道了") } })
        if (resetting) AlertDialog(onDismissRequest = { resetting = false }, title = { Text("删除本机全部课程？") },
            text = { Text("此操作无法撤销；无法读取的原始课表也将被覆盖。") },
            dismissButton = { TextButton(onClick = { resetting = false }) { Text("取消") } },
            confirmButton = { TextButton(onClick = {
                try {
                    val empty = Schedule.empty(today)
                    repository.save(empty)
                    schedule = empty
                    loadFailed = false
                    week = 1
                    resetting = false
                } catch (e: Exception) { resetting = false; error = "重置失败：${e.message}" }
            }) { Text("确认删除") } })
    }
}

@Composable
private fun DayColumn(schedule: Schedule, week: Int, day: Int, onEdit: (Course) -> Unit, modifier: Modifier) {
    val courses = schedule.coursesAt(week, day)
    LazyColumn(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Text("${dayNames[day - 1]}\n${schedule.dateAt(week, day)}", style = MaterialTheme.typography.titleMedium) }
        if (courses.isEmpty()) item { Text("无课程", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        items(courses, key = { it.id }) { course ->
            Card(onClick = { onEdit(course) }, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(course.name, style = MaterialTheme.typography.titleMedium)
                    Text("第 ${course.startPeriod}–${course.endPeriod} 节")
                    if (course.location.isNotBlank()) Text(course.location)
                    if (course.teacher.isNotBlank()) Text(course.teacher)
                }
            }
        }
    }
}

@OptIn(kotlin.uuid.ExperimentalUuidApi::class)
@Composable
private fun CourseEditor(original: Course?, day: Int, onDismiss: () -> Unit, onSave: (Course) -> Unit, onDelete: (Course) -> Unit) {
    var name by remember { mutableStateOf(original?.name.orEmpty()) }
    var location by remember { mutableStateOf(original?.location.orEmpty()) }
    var teacher by remember { mutableStateOf(original?.teacher.orEmpty()) }
    var weekday by remember { mutableStateOf((original?.weekday ?: day).toString()) }
    var start by remember { mutableStateOf((original?.startPeriod ?: 1).toString()) }
    var end by remember { mutableStateOf((original?.endPeriod ?: 2).toString()) }
    var weeks by remember { mutableStateOf(original?.weeks?.joinToString(",") ?: "1-16") }
    var error by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf(false) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(if (original == null) "添加课程" else "编辑课程") },
        text = {
            Column(Modifier.imePadding().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                EditorField(name, { name = it }, "课程名称")
                EditorField(location, { location = it }, "教室")
                EditorField(teacher, { teacher = it }, "教师")
                EditorField(weekday, { weekday = it }, "星期（1–7，周日为 7）", true)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EditorField(start, { start = it }, "开始节次", true, Modifier.weight(1f))
                    EditorField(end, { end = it }, "结束节次", true, Modifier.weight(1f))
                }
                EditorField(weeks, { weeks = it }, "周次，如 1-8,10,12-16")
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                if (original != null) TextButton(onClick = { deleting = true }) { Text("删除课程") }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
        confirmButton = { TextButton(onClick = {
            try {
                val course = Course(original?.id ?: kotlin.uuid.Uuid.random().toString(), name.trim(), location.trim(), teacher.trim(),
                    weekday.toIntOrNull() ?: 0, start.toIntOrNull() ?: 0, end.toIntOrNull() ?: 0, parseWeeks(weeks))
                course.validate()
                onSave(course)
            } catch (e: Exception) { error = e.message ?: "请检查课程信息" }
        }) { Text("保存") } })
    if (deleting && original != null) AlertDialog(onDismissRequest = { deleting = false }, title = { Text("删除 ${original.name}？") },
        text = { Text("将删除此课程的全部周次记录。") },
        dismissButton = { TextButton(onClick = { deleting = false }) { Text("取消") } },
        confirmButton = { TextButton(onClick = { onDelete(original); deleting = false }) { Text("删除") } })
}

@Composable
private fun EditorField(value: String, onChange: (String) -> Unit, label: String, number: Boolean = false, modifier: Modifier = Modifier) {
    OutlinedTextField(value, onChange, modifier.fillMaxWidth(), label = { Text(label) }, singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = if (number) KeyboardType.Number else KeyboardType.Text))
}
