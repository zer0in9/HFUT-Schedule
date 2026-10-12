plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
}

kotlin {
    jvm()
    iosArm64()
    iosSimulatorArm64()
    iosX64()
    sourceSets {
        commonMain {
            // First extracted models: Android and iOS compile the same source files.
            kotlin.srcDir("../../common-logic/src/commonMain/kotlin")
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
                api("org.jetbrains.kotlinx:kotlinx-datetime:0.6.2")
            }
        }
        commonTest.dependencies { implementation(kotlin("test")) }
    }
}
