package com.hfut.schedule.shared

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.daysUntil
import kotlinx.datetime.plus
import kotlinx.datetime.todayIn
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.time.Clock
import kotlin.time.ExperimentalTime

const val MAX_WEEKS = 30
const val MAX_PERIODS = 12

@OptIn(ExperimentalTime::class)
fun currentLocalDate(): LocalDate = Clock.System.todayIn(TimeZone.currentSystemDefault())

@Serializable
data class Course(
    val id: String,
    val name: String,
    val location: String = "",
    val teacher: String = "",
    val weekday: Int,
    val startPeriod: Int,
    val endPeriod: Int,
    val weeks: List<Int>,
) {
    fun validate() {
        require(id.isNotBlank()) { "课程标识不能为空" }
        require(name.isNotBlank()) { "请填写课程名称" }
        require(weekday in 1..7) { "星期须为 1–7" }
        require(startPeriod in 1..MAX_PERIODS && endPeriod in startPeriod..MAX_PERIODS) {
            "节次须为 1–12，结束节次不能早于开始节次"
        }
        require(weeks.isNotEmpty() && weeks.all { it in 1..MAX_WEEKS }) { "周次须为 1–30" }
        require(weeks.distinct().size == weeks.size) { "周次不能重复" }
    }
}

@Serializable
data class Schedule(
    val semesterStart: String,
    val courses: List<Course> = emptyList(),
    val schemaVersion: Int = 1,
) {
    fun validate() {
        require(schemaVersion == 1) { "暂不支持此课表版本" }
        val start = LocalDate.parse(semesterStart)
        require(start.dayOfWeek.ordinal == 0) { "开学日期须为第一周的周一" }
        courses.forEach(Course::validate)
        require(courses.map { it.id }.distinct().size == courses.size) { "课程标识重复" }
    }

    // Return the real week, including 0 / negative / >30 outside the semester.
    fun weekOn(date: LocalDate): Int {
        val days = LocalDate.parse(semesterStart).daysUntil(date)
        return if (days >= 0) days / 7 + 1 else (days - 6) / 7 + 1
    }

    fun dateAt(week: Int, weekday: Int): LocalDate =
        LocalDate.parse(semesterStart).plus((week - 1) * 7 + weekday - 1, DateTimeUnit.DAY)

    fun coursesAt(week: Int, weekday: Int): List<Course> = courses
        .filter { it.weekday == weekday && week in it.weeks }
        .sortedWith(compareBy(Course::startPeriod, Course::endPeriod, Course::name))

    companion object {
        fun empty(today: LocalDate) = Schedule(
            semesterStart = today.plus(-today.dayOfWeek.ordinal, DateTimeUnit.DAY).toString()
        )
    }
}

/** Platform adapters store one versioned snapshot. Never silently replace unreadable data. */
interface ScheduleStorage {
    fun read(): String?
    fun write(value: String)
}

class ScheduleRepository(private val storage: ScheduleStorage) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun load(today: LocalDate): Schedule = storage.read()?.let {
        json.decodeFromString<Schedule>(it).also(Schedule::validate)
    } ?: Schedule.empty(today)

    fun save(schedule: Schedule) {
        schedule.validate()
        storage.write(json.encodeToString(schedule))
    }
}

/** Accept explicit weeks and inclusive ranges, e.g. 1-8,10,12-16. */
fun parseWeeks(text: String): List<Int> {
    val result = text.replace('，', ',').split(',').flatMap { part ->
        val ends = part.trim().split('-').map { it.trim().toIntOrNull() }
        require(ends.size in 1..2 && ends.all { it != null && it in 1..MAX_WEEKS }) {
            "周次格式示例：1-8,10,12-16，范围为 1–30"
        }
        val first = ends.first()!!
        val last = ends.last()!!
        require(first <= last) { "周次范围不能倒置" }
        (first..last).toList()
    }.distinct().sorted()
    require(result.isNotEmpty()) { "请填写周次" }
    return result
}
