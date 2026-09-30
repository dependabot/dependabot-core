// spec/fixtures/projects/sample_project/build.gradle.kts
plugins {
    java
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("com.google.guava:guava:32.1.2-jre")
    testImplementation("junit:junit:4.13.2")
}
