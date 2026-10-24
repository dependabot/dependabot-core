plugins {
    java
}

dependencies {
    implementation("com.example:lib-instrumentation:4.0.0-RC1")
    implementation("com.example:error-handler:4.0.0-RC1")
    implementation("com.example:error-handler-extra:4.0.0-RC1")
    implementation(group = "com.example", name = "error-handler-legacy", version = "4.0.0-RC1")
    implementation(group = "com.example", name = "error-handler", version = "4.0.0-RC1")
    runtimeOnly(group = "com.example", name = /* artifact */ "error-handler", version = "4.0.0-RC1")
    testImplementation("org.other:error-handler:4.0.0-RC1")
    implementation(group = "org.other", name = "error-handler", version = "4.0.0-RC1").exclude(group = "com.example", module = "legacy")
    implementation("org.other:legacy:4.0.0-RC1").because("""com.example:error-handler:4.0.0-RC1 replaces it""")
}
