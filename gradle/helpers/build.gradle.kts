plugins {
    kotlin("jvm") version "1.9.0"
    application
}

application {
    mainClass.set("dependabot.gradle.MainKt")
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.gradle:gradle-tooling-api:8.5") // Use the appropriate Gradle version
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.0")
}
