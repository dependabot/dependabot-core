import build._
import com.typesafe.sbt.osgi.OsgiKeys
import sbtcrossproject.CrossPlugin.autoImport.crossProject

val minSuccessfulTests = settingKey[Int]("")

/*
 * NOTICE if you are a contributor who only cares about the JVM, create a file
 * `local.sbt` containing
 *
 *   onLoad in Global := { s => "project rootJVM" :: s }
 *
 * and regular commands such as "compile" / "test" will skip over all the
 * scalajs / scala-native stuff.
 */

lazy val jsProjects = Seq[ProjectReference](
  coreJS, effectJS, iterateeJS, scalacheckBindingJS, testsJS
)

lazy val jvmProjects = Seq[ProjectReference](
  coreJVM, effectJVM, iterateeJVM, scalacheckBindingJVM, testsJVM, example
)

lazy val nativeProjects = Seq[ProjectReference](
  coreNative, effectNative, iterateeNative, nativeTest, scalacheckBindingNative
)

lazy val scalaz = Project(
  id = "scalaz",
  base = file(".")
).settings(
  standardSettings,
  description := "scalaz unidoc",
  artifacts := Classpaths.artifactDefs(Seq(packageDoc in Compile, makePom in Compile)).value,
  packagedArtifacts := Classpaths.packaged(Seq(packageDoc in Compile, makePom in Compile)).value,
  pomPostProcess := { node =>
    import scala.xml._
    import scala.xml.transform._
    val rule = new RewriteRule {
      override def transform(n: Node) =
        if (n.label == "dependencies") NodeSeq.Empty else n
    }
    new RuleTransformer(rule).transform(node)(0)
  },
  unidocProjectFilter in (ScalaUnidoc, unidoc) := {
    (jsProjects ++ nativeProjects :+ (site: ProjectReference)).foldLeft(inAnyProject)((acc, a) => acc -- inProjects(a))
  },
  Defaults.packageTaskSettings(packageDoc in Compile, (unidoc in Compile).map(_.flatMap(Path.allSubpaths)))
).aggregate(
  jvmProjects ++ jsProjects : _*
).enablePlugins(ScalaUnidocPlugin)

lazy val rootNative = Project(
  rootNativeId,
  file("rootNative")
).settings(
  standardSettings,
  notPublish
).aggregate(nativeProjects: _*)

lazy val rootJS = Project(
  "rootJS",
  file("rootJS")
).settings(
  standardSettings,
  notPublish
).aggregate(jsProjects: _*)

lazy val rootJVM = Project(
  "rootJVM",
  file("rootJVM")
).settings(
  standardSettings,
  notPublish
).aggregate(jvmProjects: _*)

lazy val coreJVM = core.jvm
lazy val coreJS  = core.js
lazy val coreNative = core.native

lazy val effectJVM = effect.jvm
lazy val effectJS  = effect.js
lazy val effectNative = effect.native

lazy val iterateeJVM = iteratee.jvm
lazy val iterateeJS  = iteratee.js
lazy val iterateeNative = iteratee.native

lazy val example = Project(
  id = "example",
  base = file("example")
).settings(
  standardSettings,
  name := "scalaz-example",
  notPublish,
  scalacOptions in (Compile, compile) -= "-Xlint:adapted-args"
).dependsOn(
  coreJVM, iterateeJVM
)
lazy val scalacheckBinding =
  crossProject(JVMPlatform, JSPlatform, NativePlatform).crossType(ScalazCrossType)
    .in(file("scalacheck-binding"))
    .settings(standardSettings)
    .settings(
      name := "scalaz-scalacheck-binding",
      scalacOptions in (Compile, compile) -= "-Ywarn-value-discard",
      libraryDependencies += "org.scalacheck" %%% "scalacheck" % scalaCheckVersion.value,
      osgiExport("scalaz.scalacheck")
    )
    .dependsOn(core, iteratee)
    .jsSettings(scalajsProjectSettings)
    .nativeSettings(nativeSettings)

lazy val scalacheckBindingJVM = scalacheckBinding.jvm
lazy val scalacheckBindingJS  = scalacheckBinding.js
lazy val scalacheckBindingNative = scalacheckBinding.native

lazy val tests = crossProject(JSPlatform, JVMPlatform).crossType(ScalazCrossType)
  .settings(standardSettings)
  .settings(
    name := "scalaz-tests",
    notPublish,
    testOptions in Test += {
      val scalacheckOptions = Seq(
        "-maxSize", "5",
        "-workers", "1",
        "-maxDiscardRatio", "50",
        "-minSuccessfulTests", minSuccessfulTests.value.toString
      )
      Tests.Argument(TestFrameworks.ScalaCheck, scalacheckOptions: _*)
    },
    libraryDependencies += "org.scalacheck" %%% "scalacheck" % scalaCheckVersion.value % "test")
  .jvmSettings(
    minSuccessfulTests := 33
  )
  .jsSettings(
    minSuccessfulTests := 10
  )
  .dependsOn(core, effect, iteratee, scalacheckBinding)
  .jsSettings(scalajsProjectSettings)

lazy val testsJVM = tests.jvm
lazy val testsJS  = tests.js

// can't use "sbt test"
// https://github.com/rickynils/scalacheck/issues/396
lazy val nativeTest = Project(nativeTestId, file("nativeTest")).enablePlugins(ScalaNativePlugin)
  .settings(
    standardSettings,
    nativeSettings,
    notPublish
  )
  .dependsOn(iterateeNative)

lazy val site = Project(
  id = "site",
  base = file("site")
).settings(
  standardSettings,
  name := "scalaz-site",
  notPublish,
  scalacOptions in (Compile, compile) -= "-Xlint:adapted-args",
).dependsOn(
  coreJVM
).enablePlugins(
  MicrositesPlugin
).settings(
  scalacOptions ~= { _ filterNot (_ startsWith "-Ywarn") },
  scalacOptions ~= { _ filterNot (_ startsWith "-Xlint") },
  micrositeFooterText := Some("""
                                |<p>&copy; 2018 <a href="https://github.com/scalaz/scalaz">Scalaz Maintainers</a></p>
                                |""".stripMargin),
  micrositeDocumentationUrl := s"https://javadoc.io/doc/org.scalaz/scalaz-core_2.12/${(version in Compile).value}",
  micrositeDocumentationLabelDescription := "Scaladoc",
  micrositeName := "Scalaz",
  micrositeDescription := "Scalaz",
  micrositeAuthor := "Scalaz contributors",
  micrositeOrganizationHomepage := "https://github.com/scalaz/scalaz",
  micrositeGitterChannelUrl := "scalaz/scalaz",
  micrositeGitHostingUrl := "https://github.com/scalaz/scalaz",
  micrositeGithubOwner := "scalaz",
  micrositeGithubRepo := "scalaz",
  micrositeFavicons := Seq(microsites.MicrositeFavicon("favicon.png", "512x512")),
  micrositeBaseUrl := "/7",
  micrositePalette := Map(
    "brand-primary"   -> "#ED2124",
    "brand-secondary" -> "#251605",
    "brand-tertiary"  -> "#491119",
    "gray-dark"       -> "#453E46",
    "gray"            -> "#837F84",
    "gray-light"      -> "#E3E2E3",
    "gray-lighter"    -> "#F4F3F4",
    "white-color"     -> "#FFFFFF"
  )
)
