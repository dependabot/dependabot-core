scalaVersion := "2.13.12"

val catsVersion = "2.10.0"
val akkaVersion = "2.8.5"

libraryDependencies += "org.typelevel" %% "cats-core" % catsVersion
libraryDependencies += "com.typesafe.akka" %% "akka-actor" % akkaVersion
libraryDependencies += "com.google.guava" % "guava" % "33.0.0-jre"
