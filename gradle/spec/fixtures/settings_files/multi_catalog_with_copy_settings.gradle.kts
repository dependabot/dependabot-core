dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from(files("gradle/libs.versions.toml"))
        }
        create("tools") {
            from(files("gradle/tools.versions.toml"))
        }
        create("plugins") {
            from(files("gradle/plugins.versions.toml"))
        }
    }
}

gradle.rootProject {
    tasks.register<Copy>("copyScripts") {
        from(files("scripts/init.gradle"))
        into(layout.buildDirectory.dir("scripts"))
    }
}
