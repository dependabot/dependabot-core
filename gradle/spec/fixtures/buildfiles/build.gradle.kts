group "me.minidigger"

apply(plugin = "com.github.johnrengelman.shadow")

task copyToServer(type: Copy) {
    from shadowJar
    into testServerFolder
}

shadowJar {
    mergeServiceFiles()
    configurations = listOf(project.configurations.compile)

    //relocate "org.bstats", "com.voxelgameslib.voxelgameslib.metrics" TODO relocate bstats

    manifest {
        attributes "Implementation-Version": project.version + "@" + revision
    }
}

val devNull = new OutputStream() {
  @Override
  public void write(int b) {}
}


build.dependsOn shadowJar

dependencies {
    implementation(project(":ChatMenuAPI"))

    // Some details about "co.aikar:acf-paper", version = "0.5.0-SNAPSHOT"
    implementation(group = "co.aikar", name = "acf-paper", version = "0.5.0-SNAPSHOT", changing: true)
    implementation(group = "com.google.inject", name = "guice", version = "4.2.0")
    implementation(group = "com.google.code.findbugs", name = "jsr305", version = "3.0.2")
    implementation(group = "de.davidbilge", name = "jskill", version = "1.1-SNAPSHOT")
    implementation(group = "net.lingala.zip4j", name = "zip4j", version = "1.3.2")
    implementation(group = "co.aikar", name = "taskchain-bukkit", version = "3.6.0")
    implementation(group = "net.kyori", name = "text", version = "1.12-1.4.0")
    implementation(group = "org.bstats", name = "bstats-bukkit", version = "1.2")
    implementation(group = "com.bugsnag", name = "bugsnag", version = "3.1.5")
    implementation(group = "com.zaxxer", name = "HikariCP", version = "2.7.8")
    implementation(group = "org.eclipse.jgit", name = "org.eclipse.jgit", version = "4.11.0.201803080745-r")
    implementation(group = "org.hibernate", name = "hibernate-core", version = "5.3.0.CR1")
    implementation(group = "com.dumptruckman.minecraft", name = "JsonConfiguration", version = "1.1")
    implementation(group = "org.inventivetalent", name = "mc-wrappers", version = "1.0.3-SNAPSHOT")
    implementation(group = "io.github.lukehutch", name = "fast-classpath-scanner", version = "2.18.1")
    implementation(group = "org.objenesis", name = "objenesis", version = "2.6")

    implementation((group = "org.inventivetalent", name = "menubuilder", version = "1.0.2") {
        exclude group = "org.bukkit"
    })
    implementation((group = "org.mineskin", name = "java-client", version = "1.0.1-SNAPSHOT") {
        exclude group = "junit"
    })
    implementation((group = "org.inventivetalent", name = "reflectionhelper", version = "1.13.0-SNAPSHOT") {
        exclude group = "junit"
    })
}

task createPom() {
    pom {
        project {
            groupId "com.voxelgameslib"
            artifactId "dependencies"
            version version
        }
    }.writeTo("pom.xml")
}
