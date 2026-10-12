plugins {
    kotlin("multiplatform")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

kotlin {
    // JVM also provides a Linux compile check for the shared Compose UI.
    jvm()
    listOf(iosArm64(), iosSimulatorArm64(), iosX64()).forEach {
        it.binaries.framework {
            baseName = "ScheduleShared"
            isStatic = true
            binaryOption("bundleId", "com.hfut.schedule.shared")
        }
    }
    sourceSets {
        commonMain.dependencies {
            implementation(project(":core"))
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
        }
        jvmMain.dependencies { implementation(compose.desktop.currentOs) }
    }
}
