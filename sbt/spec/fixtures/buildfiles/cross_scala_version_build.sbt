name := "ScalaClientOfMutabilityDetector"

version := "0.1"

scalaVersion := "2.11.5"

resolvers += "Local Maven Repository" at Path.userHome.asURL + "/.m2/repository"

libraryDependencies += "junit" % "junit-dep" % "4.11" % "test"

libraryDependencies += "org.scalatest" %% "scalatest" % "2.2.5" % "test"

libraryDependencies += "org.mutabilitydetector" % "MutabilityDetector" % "0.9.4-SNAPSHOT" % "test"
