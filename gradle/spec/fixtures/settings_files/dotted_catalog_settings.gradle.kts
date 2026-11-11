dependencyResolutionManagement.versionCatalogs {
    create("libs") {
        from(files("gradle/libs.versions.toml"))
    }
}

dependencyResolutionManagement {
    versionCatalogs.create("tools") {
        from(files("gradle/tools.versions.toml"))
    }
    versionCatalogs.register("plugins") {
        from(files("gradle/plugins.versions.toml"))
    }
}
