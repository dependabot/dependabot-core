import org.jetbrains.kotlin.config.KotlinCompilerVersion

group "de.fhaachen"
version "1.0-SNAPSHOT"

plugins {
    id("kotlin")
    id("com.github.johnrengelman.shadow")
    id("org.springframework.boot") version "2.0.5.RELEASE" apply false
    id("com.google.protobuf") version "0.8.4" apply false
    kotlin("jvm") version "1.3.72"

    val helmVersion = "1.6.0"
    id("org.unbroken-dome.helm") version helmVersion apply false
}

buildscript {
    extra["kotlinVersion"] = "1.2.61"

    repositories {
        jcenter()
        maven(url = "https://dl.bintray.com/magnusja/maven")
        maven("https://kotlin.bintray.com/kotlinx/")
        google()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        classpath("com.github.jengelman.gradle.plugins:shadow:2.0.2")
        classpath("com.android.tools.build:gradle:3.1.2")
    }
}

val kotlinVersion: String by extra

apply from = "gradle/dependencies.gradle.kts"

allprojects {
    repositories {
        jcenter()
        maven("https://dl.bintray.com/magnusja/maven")
        google()
    }

    task downloadDependencies {
        doLast {
            configurations.all {
                try {
                    it.files
                } catch (e) {
                    project.logger.info(e.message)
                }
            }
        }
    }
}

// Here to ensure we don"t parse SCM URLs as dependency declarations
scm {
    url "scm:git@github.com:mapfish/mapfish-print.git"
    connection "scm:git@github.com:mapfish/mapfish-print.git"
    developerConnection "scm:git@github.com:mapfish/mapfish-print.git"
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jre8:$kotlinVersion")
    implementation("com.sparkjava:spark-core:2.5.4@jar")
    implementation("org.slf4j:slf4j-simple:1.7.21")
    implementation("com.github.jeremyh:jBCrypt:master-SNAPSHOT")
    implementation("com.github.salomonbrys.kotson:kotson:2.5.0")
    implementation("mysql:mysql-connector-java:5.1.6")
    implementation("com.github.heremaps:oksse:be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7")
}

jar {
    manifest {
        attributes "Main-Class" = "de.fhaachen.cryptoclicker.MainKt"
    }
}

shadowJar {
    mergeServiceFiles()
    configurations = listOf(project.configurations.compile)
}

compileKotlin {
    kotlinOptions.jvmTarget = "1.8"
}
compileTestKotlin {
    kotlinOptions.jvmTarget = "1.8"
}
build.dependsOn shadowJar

configure(subprojects.findAll { !it.name.startsWith("examples/") }) {
    apply(plugin = "io.spring.dependency-management")
    apply(plugin = "maven")

    repositories {
        jcenter()
    }

    project.afterEvaluate {
        project.tasks.findByName("install")?.dependsOn(tasks.findByName("assemble"))
    }

    dependencyManagement {
        overriddenByDependencies = false

        imports {
            mavenBom "org.junit:junit-bom:5.3.1"
            mavenBom "org.springframework.boot:spring-boot-dependencies:2.0.5.RELEASE"
            mavenBom "org.testcontainers:testcontainers-bom:1.9.1"
        }

        dependencies {
            dependency "org.projectlombok:lombok:1.18.2"

            dependency "org.lognet:grpc-spring-boot-starter:2.4.2"

            dependency "org.pf4j:pf4j:2.4.0"

            dependencySet(group = "com.google.protobuf", version = "3.6.1") {
                entry "protoc"
                entry "protobuf-java"
                entry "protobuf-java-util"
            }

            dependency "org.apache.kafka:kafka-clients:3.6.1"

            dependency "com.google.auto.service:auto-service:1.0-rc4"

            dependencySet(group = "io.grpc", version = "1.15.1") {
                entry "grpc-netty"
                entry "grpc-core"
                entry "grpc-services"
                entry "grpc-protobuf"
                entry "grpc-stub"
                entry "protoc-gen-grpc-java"
            }

            dependency "com.salesforce.servicelibs:reactor-grpc-stub:0.9.0"

            dependency "org.awaitility:awaitility:3.1.2"
        }
    }
}

extra.apply {
    set("compileSdkVersion", 27)
    set("buildToolsVersion", "27.0.3")

    // Support
    set("supportVersion", "27.1.1")

    // set("commentedVersion", "27.1.1")

    set("findPropertyVersion", project.findProperty("findPropertyVersion") ?: "27.1.1")

    set("hasPropertyVersion", if(project.hasProperty("hasPropertyVersion")) project.getProperty("hasPropertyVersion") else "27.1.1")
}

extra.set("javaVersion", "11")

extra["versions"] = mapOf(
  "okhttp"                  to "3.12.1",
  "findPropertyVersion"     to project.findProperty("findPropertyVersion") ?: "1.0.0",
  "hasPropertyVersion"      to if(project.hasProperty("hasPropertyVersion")) project.getProperty("hasPropertyVersion") else "1.0.0"
)
