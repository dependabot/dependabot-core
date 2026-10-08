plugins {
    id("org.jetbrains.kotlin.jvm") version "2.1.21"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.21"
    id("com.github.johnrengelman.shadow") version "8.1.1"
    application
}

application {
    mainClass.set("dependabot.gradle.MainKt")
}

repositories {
    // Required for gradle-tooling-api
    maven { url = uri("https://repo.gradle.org/gradle/libs-releases") }
    // Required for kotlinx and Kotlin plugins
    mavenCentral()
}

dependencies {
    // Kotlin standard library
    implementation("org.jetbrains.kotlin:kotlin-stdlib")

    // Kotlinx serialization (latest stable)
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")

    // Gradle Tooling API (match your expected runtime Gradle version)
    implementation("org.gradle:gradle-tooling-api:8.14.2")

    // Required SLF4J implementation for Tooling API logging
    runtimeOnly("org.slf4j:slf4j-simple:2.0.13")
}

tasks.withType<com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar> {
    archiveBaseName.set("gradle-helper")
    archiveClassifier.set("") // produces gradle-helper.jar

    // Add main class to manifest to make the JAR executable
    manifest {
        attributes["Main-Class"] = "dependabot.gradle.MainKt"
    }
}
