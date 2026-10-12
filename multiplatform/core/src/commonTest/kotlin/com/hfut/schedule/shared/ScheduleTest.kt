package com.hfut.schedule.shared

import kotlinx.datetime.LocalDate
import kotlin.test.*

class ScheduleTest {
    private val monday = LocalDate(2026, 9, 7)
    private fun course(id: String = "1", day: Int = 1, start: Int = 1, weeks: List<Int> = listOf(1, 3)) =
        Course(id, "高等数学", "教学楼 101", "", day, start, start + 1, weeks)

    @Test fun weekBoundariesAndDates() {
        val schedule = Schedule(monday.toString())
        assertEquals(1, schedule.weekOn(monday))
        assertEquals(1, schedule.weekOn(LocalDate(2026, 9, 13)))
        assertEquals(2, schedule.weekOn(LocalDate(2026, 9, 14)))
        assertEquals(0, schedule.weekOn(LocalDate(2026, 9, 6)))
        assertEquals(-1, schedule.weekOn(LocalDate(2026, 8, 30)))
        assertEquals(LocalDate(2026, 9, 20), schedule.dateAt(2, 7))
        assertEquals(31, schedule.weekOn(schedule.dateAt(31, 1)))
    }

    @Test fun emptyScheduleStartsOnMondayAcrossYearBoundary() {
        assertEquals("2025-12-29", Schedule.empty(LocalDate(2026, 1, 1)).semesterStart)
    }

    @Test fun filtersWeeksAndWeekdaysAndSortsPeriods() {
        val early = course("early")
        val late = course("late", start = 5)
        val sunday = course("sunday", day = 7)
        val schedule = Schedule(monday.toString(), courses = listOf(late, sunday, early))
        assertEquals(listOf(early, late), schedule.coursesAt(1, 1))
        assertTrue(schedule.coursesAt(2, 1).isEmpty())
        assertEquals(listOf(sunday), schedule.coursesAt(3, 7))
    }

    @Test fun validatesWeekInput() {
        assertEquals(listOf(1, 2, 3, 5, 7), parseWeeks("1-3, 5，7,2"))
        listOf("", "0", "31", "4-1", "1-999999999", "x", "1,", "1-2-3").forEach {
            assertFailsWith<IllegalArgumentException>(it) { parseWeeks(it) }
        }
    }

    @Test fun rejectsInvalidCoursesAndSchedules() {
        listOf(course().copy(name = " "), course(day = 0), course(start = 12),
            course().copy(endPeriod = 0), course(weeks = emptyList()), course(weeks = listOf(1, 1))).forEach {
            assertFailsWith<IllegalArgumentException> { it.validate() }
        }
        assertFailsWith<IllegalArgumentException> { Schedule("2026-09-08").validate() }
        assertFailsWith<IllegalArgumentException> { Schedule(monday.toString(), courses = listOf(course(), course())).validate() }
    }

    private class MemoryStorage(var value: String? = null) : ScheduleStorage {
        override fun read() = value
        override fun write(value: String) { this.value = value }
    }

    @Test fun roundTripsUnicodeAndUpdatesAndDeletion() {
        val storage = MemoryStorage()
        val repository = ScheduleRepository(storage)
        val schedule = Schedule(monday.toString(), courses = listOf(course().copy(name = "数学\n\"分析\"")))
        repository.save(schedule)
        assertEquals(schedule, repository.load(monday))
        val edited = schedule.copy(courses = listOf(course().copy(location = "新教室")))
        repository.save(edited)
        assertEquals("新教室", repository.load(monday).courses.single().location)
        repository.save(edited.copy(courses = emptyList()))
        assertTrue(repository.load(monday).courses.isEmpty())
    }

    @Test fun badDataIsPreservedAndInvalidWritesDoNotReplaceIt() {
        val storage = MemoryStorage("broken data")
        val repository = ScheduleRepository(storage)
        assertFails { repository.load(monday) }
        assertEquals("broken data", storage.value)
        assertFails { repository.save(Schedule("not a date")) }
        assertEquals("broken data", storage.value)
        storage.value = """{"schemaVersion":2,"semesterStart":"2026-09-07","courses":[]}"""
        assertFailsWith<IllegalArgumentException> { repository.load(monday) }
    }
}
