scalaVersion := "2.13.12"

libraryDependencies ++= Seq(
  "org.typelevel" %% "cats-core" % "2.10.0",
  "com.typesafe.akka" %% "akka-actor" % "2.8.5",
  "com.google.guava" % "guava" % "33.0.0-jre",
  "org.scalatest" %% "scalatest" % "3.2.17" % "test"
)
