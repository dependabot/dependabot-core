# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/sbt/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Sbt::FileUpdater do
  let(:dependency_files) { [buildfile] }
  let(:dependencies) { [dependency] }
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.sbt" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "com.google.guava:guava",
      version: "33.1.0-jre",
      requirements: [{
        file: "build.sbt",
        requirement: "33.1.0-jre",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_requirements: [{
        file: "build.sbt",
        requirement: "33.0.0-jre",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_version: "33.0.0-jre",
      package_manager: "sbt"
    )
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      expect(updated_files).to all(be_a(Dependabot::DependencyFile))
    end

    its(:length) { is_expected.to eq(1) }

    context "with a basic build.sbt" do
      let(:buildfile_fixture_name) { "basic_build.sbt" }

      it "updates the version string" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"com.google.guava" % "guava" % "33.1.0-jre"')
        expect(updated_content).not_to include('"com.google.guava" % "guava" % "33.0.0-jre"')
      end

      it "preserves other dependencies" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"org.typelevel" %% "cats-core" % "2.10.0"')
        expect(updated_content).to include('"com.typesafe.akka" %% "akka-actor" % "2.8.5"')
      end
    end

    context "with a cross-versioned dependency (%%)" do
      let(:buildfile_fixture_name) { "basic_build.sbt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.typelevel:cats-core_2.13",
          version: "2.11.0",
          requirements: [{
            file: "build.sbt",
            requirement: "2.11.0",
            groups: [],
            source: nil,
            metadata: { packaging_type: "cross-versioned" }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "2.10.0",
            groups: [],
            source: nil,
            metadata: { packaging_type: "cross-versioned" }
          }],
          previous_version: "2.10.0",
          package_manager: "sbt"
        )
      end

      it "updates the cross-versioned dependency" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"org.typelevel" %% "cats-core" % "2.11.0"')
        expect(updated_content).not_to include('"org.typelevel" %% "cats-core" % "2.10.0"')
      end
    end

    context "with a Seq-style dependency declaration" do
      let(:buildfile_fixture_name) { "seq_build.sbt" }

      it "updates the version in the Seq block" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"com.google.guava" % "guava" % "33.1.0-jre"')
        expect(updated_content).not_to include('"com.google.guava" % "guava" % "33.0.0-jre"')
      end

      it "preserves other Seq entries" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"org.typelevel" %% "cats-core" % "2.10.0"')
        expect(updated_content).to include('"com.typesafe.akka" %% "akka-actor" % "2.8.5"')
      end
    end

    context "with a commented build file" do
      let(:buildfile_fixture_name) { "commented_build.sbt" }

      it "updates the real dependency, not the commented one" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"com.google.guava" % "guava" % "33.1.0-jre"')
        expect(updated_content).not_to include(
          'libraryDependencies += "com.google.guava" % "guava" % "33.0.0-jre"'
        )
      end
    end

    context "with a multiproject build file" do
      let(:buildfile_fixture_name) { "multiproject_build.sbt" }

      it "updates all occurrences of the dependency" do
        updated_content = updated_files.first.content
        expect(updated_content.scan('"33.1.0-jre"').length).to eq(2)
        expect(updated_content).not_to include('"33.0.0-jre"')
      end
    end

    context "with a plugin dependency" do
      let(:dependency_files) { [buildfile, plugins_file] }
      let(:plugins_file) do
        Dependabot::DependencyFile.new(
          name: "project/plugins.sbt",
          content: fixture("buildfiles", "plugins.sbt")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.eed3si9n:sbt-assembly",
          version: "2.2.0",
          requirements: [{
            file: "project/plugins.sbt",
            requirement: "2.2.0",
            groups: ["plugins"],
            source: nil,
            metadata: nil
          }],
          previous_requirements: [{
            file: "project/plugins.sbt",
            requirement: "2.1.5",
            groups: ["plugins"],
            source: nil,
            metadata: nil
          }],
          previous_version: "2.1.5",
          package_manager: "sbt"
        )
      end

      it "updates the plugin version" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.2.0")')
        expect(updated_content).not_to include('"2.1.5"')
      end

      it "preserves other plugins" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.5.2")')
      end
    end

    context "with a val-based version" do
      let(:buildfile_fixture_name) { "val_based_build.sbt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.typelevel:cats-core_2.13",
          version: "2.11.0",
          requirements: [{
            file: "build.sbt",
            requirement: "2.11.0",
            groups: [],
            source: nil,
            metadata: {
              property_name: "catsVersion",
              property_source: "build.sbt",
              packaging_type: "cross-versioned"
            }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "2.10.0",
            groups: [],
            source: nil,
            metadata: {
              property_name: "catsVersion",
              property_source: "build.sbt",
              packaging_type: "cross-versioned"
            }
          }],
          previous_version: "2.10.0",
          package_manager: "sbt"
        )
      end

      it "updates the val declaration" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('val catsVersion = "2.11.0"')
        expect(updated_content).not_to include('val catsVersion = "2.10.0"')
      end

      it "does not change the dependency line referencing the val" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('"org.typelevel" %% "cats-core" % catsVersion')
      end
    end

    context "with a val defined in a Scala file" do
      let(:buildfile_fixture_name) { "scala_file_vals_build.sbt" }
      let(:scala_file) do
        Dependabot::DependencyFile.new(
          name: "project/Dependencies.scala",
          content: fixture("buildfiles", "project/Dependencies.scala"),
          support_file: true
        )
      end
      let(:dependency_files) { [buildfile, scala_file] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.typelevel:cats-core_2.13",
          version: "2.11.0",
          requirements: [{
            file: "build.sbt",
            requirement: "2.11.0",
            groups: [],
            source: nil,
            metadata: {
              property_name: "catsVersion",
              property_source: "project/Dependencies.scala",
              packaging_type: "cross-versioned"
            }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "2.10.0",
            groups: [],
            source: nil,
            metadata: {
              property_name: "catsVersion",
              property_source: "project/Dependencies.scala",
              packaging_type: "cross-versioned"
            }
          }],
          previous_version: "2.10.0",
          package_manager: "sbt"
        )
      end

      it "updates the val in the Scala file" do
        scala_updated = updated_files.find { |f| f.name == "project/Dependencies.scala" }
        expect(scala_updated).not_to be_nil
        expect(scala_updated.content).to include('val catsVersion = "2.11.0"')
        expect(scala_updated.content).not_to include('val catsVersion = "2.10.0"')
      end
    end

    context "with an SBT version update in build.properties" do
      let(:properties_file) do
        Dependabot::DependencyFile.new(
          name: "project/build.properties",
          content: fixture("buildfiles", "build.properties")
        )
      end
      let(:dependency_files) { [buildfile, properties_file] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.scala-sbt:sbt",
          version: "1.10.0",
          requirements: [{
            file: "project/build.properties",
            requirement: "1.10.0",
            groups: [],
            source: nil,
            metadata: { property_source: "build.properties" }
          }],
          previous_requirements: [{
            file: "project/build.properties",
            requirement: "1.9.8",
            groups: [],
            source: nil,
            metadata: { property_source: "build.properties" }
          }],
          previous_version: "1.9.8",
          package_manager: "sbt"
        )
      end

      it "updates the SBT version in build.properties" do
        properties_updated = updated_files.find { |f| f.name == "project/build.properties" }
        expect(properties_updated).not_to be_nil
        expect(properties_updated.content).to include("sbt.version=1.10.0")
        expect(properties_updated.content).not_to include("sbt.version=1.9.8")
      end
    end

    context "with a scalaVersion update" do
      let(:buildfile_fixture_name) { "basic_build.sbt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.scala-lang:scala-library",
          version: "2.13.14",
          requirements: [{
            file: "build.sbt",
            requirement: "2.13.14",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "2.13.12",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_version: "2.13.12",
          package_manager: "sbt"
        )
      end

      it "updates the scalaVersion declaration" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('scalaVersion := "2.13.14"')
        expect(updated_content).not_to include('scalaVersion := "2.13.12"')
      end
    end

    context "with a Scala 3 ThisBuild scalaVersion update" do
      let(:buildfile_fixture_name) { "scala3_build.sbt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.scala-lang:scala3-library_3",
          version: "3.4.0",
          requirements: [{
            file: "build.sbt",
            requirement: "3.4.0",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "3.3.1",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_version: "3.3.1",
          package_manager: "sbt"
        )
      end

      it "updates the ThisBuild scalaVersion declaration" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('ThisBuild / scalaVersion := "3.4.0"')
        expect(updated_content).not_to include('ThisBuild / scalaVersion := "3.3.1"')
      end
    end

    context "with scalaVersion in ThisBuild (older syntax)" do
      let(:buildfile_fixture_name) { "in_this_build.sbt" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.scala-lang:scala-library",
          version: "2.12.19",
          requirements: [{
            file: "build.sbt",
            requirement: "2.12.19",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "2.12.18",
            groups: [],
            source: nil,
            metadata: { property_source: "scalaVersion" }
          }],
          previous_version: "2.12.18",
          package_manager: "sbt"
        )
      end

      it "updates the scalaVersion in ThisBuild declaration" do
        updated_content = updated_files.first.content
        expect(updated_content).to include('scalaVersion in ThisBuild := "2.12.19"')
        expect(updated_content).not_to include('scalaVersion in ThisBuild := "2.12.18"')
      end
    end

    context "with a val-based plugin version" do
      let(:dependency_files) { [buildfile, plugins_file] }
      let(:plugins_file) do
        Dependabot::DependencyFile.new(
          name: "project/plugins.sbt",
          content: fixture("buildfiles", "val_plugins.sbt")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.eed3si9n:sbt-assembly",
          version: "2.2.0",
          requirements: [{
            file: "project/plugins.sbt",
            requirement: "2.2.0",
            groups: ["plugins"],
            source: nil,
            metadata: {
              property_name: "pluginVersion",
              property_source: "project/plugins.sbt"
            }
          }],
          previous_requirements: [{
            file: "project/plugins.sbt",
            requirement: "2.1.5",
            groups: ["plugins"],
            source: nil,
            metadata: {
              property_name: "pluginVersion",
              property_source: "project/plugins.sbt"
            }
          }],
          previous_version: "2.1.5",
          package_manager: "sbt"
        )
      end

      it "updates the val declaration for the plugin version" do
        plugins_updated = updated_files.find { |f| f.name == "project/plugins.sbt" }
        expect(plugins_updated).not_to be_nil
        expect(plugins_updated.content).to include('val pluginVersion = "2.2.0"')
        expect(plugins_updated.content).not_to include('val pluginVersion = "2.1.5"')
      end
    end

    context "when no files change" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.google.guava:guava",
          version: "33.0.0-jre",
          requirements: [{
            file: "build.sbt",
            requirement: "33.0.0-jre",
            groups: [],
            source: nil,
            metadata: nil
          }],
          previous_requirements: [{
            file: "build.sbt",
            requirement: "33.0.0-jre",
            groups: [],
            source: nil,
            metadata: nil
          }],
          previous_version: "33.0.0-jre",
          package_manager: "sbt"
        )
      end

      it "raises an error" do
        expect { updated_files }.to raise_error("No files changed!")
      end
    end
  end
end
