plugins {
    id("java")
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.adevinta.motor:backend-common--lib-instrumentation:4.0.0-RC1")
    testImplementation(testFixtures("com.adevinta.motor:backend-common--lib-instrumentation:4.0.0-RC1"))
    implementation("com.adevinta.motor:feign-error-handler:4.0.0-RC1")
}
