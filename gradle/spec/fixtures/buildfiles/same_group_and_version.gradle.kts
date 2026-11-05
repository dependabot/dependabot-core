plugins {
    java
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.example:lib-instrumentation:4.0.0-RC1")
    implementation("com.example:error-handler:4.0.0-RC1")
    implementation("com.example:error-handler-extra:4.0.0-RC1")
    implementation("org.other:error-handler:4.0.0-RC1")
    implementation(group = "com.example", name = "lib-metrics", version = "4.0.0-RC1")
    testImplementation(group = "com.example", name = "test-support", version = "5.1.0")
    testImplementation(group = "com.example", name = "test-support-extra", version = "5.1.0")
}
