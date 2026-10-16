plugins {
  id("org.springframework.boot") version "2.0.5.RELEASE" apply false
  id("io.spring.dependency-management") version "1.1.7"
  id("com.google.protobuf") version "0.8.4" apply false
}

val slf4jVersion = "1.7.25"
extra["nettyVersion"] = "4.1.30.Final"
val nettyVersion: String by extra

allprojects {
  tasks.register("downloadDependencies") {
    doLast {
      configurations.all {
        try {
          files
        } catch (e: Exception) {
          project.logger.info(e.message)
        }
      }
    }
  }
}

configure(subprojects.filter { !it.name.startsWith("examples/") }) {

  dependencyManagement {
    overriddenByDependencies(false)

    imports {
      mavenBom("org.junit:junit-bom:5.3.1")
      mavenBom("org.springframework.boot:spring-boot-dependencies:2.0.5.RELEASE")
      mavenBom("org.testcontainers:testcontainers-bom:1.9.1")
    }

    dependencies {
      dependency("org.projectlombok:lombok:1.18.2")

      dependency("org.lognet:grpc-spring-boot-starter:2.4.2")

      dependency("org.pf4j:pf4j:2.4.0")

      dependencySet("com.google.protobuf:3.6.1") {
        entry("protoc")
        entry("protobuf-java")
        entry("protobuf-java-util")
      }

      dependency("org.apache.kafka:kafka-clients:3.6.1")

      dependency("com.google.auto.service:auto-service:1.0-rc4")

      dependencySet("io.grpc:1.15.1") {
        entry("grpc-netty")
        entry("grpc-core")
        entry("grpc-services")
        entry("grpc-protobuf")
        entry("grpc-stub")
        entry("protoc-gen-grpc-java")
      }

      dependency("com.salesforce.servicelibs:reactor-grpc-stub:0.9.0")

      dependency("org.awaitility:awaitility:3.1.2")

      dependencySet("org.slf4j:$slf4jVersion") {
        entry("slf4j-api")
        entry("slf4j-simple")
      }

      dependencySet("io.netty:${nettyVersion}") {
        entry("netty-handler")
        entry("netty-codec")
      }
    }
  }
}
