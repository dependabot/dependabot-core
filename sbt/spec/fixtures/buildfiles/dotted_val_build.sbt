val V = BuildInfo

scalaVersion in ThisBuild := V.scala212

libraryDependencies += "ch.epfl.scala" %% "scalafix-core" % V.scalafixVersion
libraryDependencies ++= Seq(
  "org.typelevel" %% "cats" % "0.9.0"
)
