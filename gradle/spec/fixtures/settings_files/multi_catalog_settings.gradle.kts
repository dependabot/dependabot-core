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
