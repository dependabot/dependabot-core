# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/sbt/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Sbt::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: dependency_files,
      source: source
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/sbt-project",
      directory: "/"
    )
  end

  let(:dependency_files) { [build_sbt] }

  let(:build_sbt) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end

  let(:buildfile_fixture_name) { "basic_build.sbt" }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a basic build.sbt" do
      let(:buildfile_fixture_name) { "basic_build.sbt" }

      its(:length) { is_expected.to eq(5) }

      describe "the first dependency (cross-versioned)" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.typelevel:cats-core_2.13" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.typelevel:cats-core_2.13")
          expect(dependency.version).to eq("2.10.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.10.0",
              file: "build.sbt",
              source: nil,
              groups: [],
              metadata: { packaging_type: "cross-versioned" }
            }]
          )
        end
      end

      describe "a Java dependency (not cross-versioned)" do
        subject(:dependency) { dependencies.find { |d| d.name == "com.google.guava:guava" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("com.google.guava:guava")
          expect(dependency.version).to eq("33.0.0-jre")
          expect(dependency.requirements).to eq(
            [{
              requirement: "33.0.0-jre",
              file: "build.sbt",
              source: nil,
              groups: [],
              metadata: nil
            }]
          )
        end
      end

      describe "a test-scoped dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.scalatest:scalatest_2.13" } }

        it "is parsed with the correct version" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("3.2.17")
        end
      end
      describe "the scalaVersion dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.scala-lang:scala-library" } }

        it "is parsed as a dependency" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("2.13.12")
          expect(dependency.requirements.first[:metadata]).to eq({ property_source: "scalaVersion" })
        end
      end
    end

    context "with val-based versioning" do
      let(:buildfile_fixture_name) { "val_based_build.sbt" }

      its(:length) { is_expected.to eq(4) }

      describe "a val-referenced dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.typelevel:cats-core_2.13" } }

        it "resolves the val to the correct version" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("2.10.0")
          expect(dependency.requirements.first[:metadata]).to include(
            property_name: "catsVersion",
            property_source: "build.sbt"
          )
        end
      end

      describe "a literal-versioned dependency in the same file" do
        subject(:dependency) { dependencies.find { |d| d.name == "com.google.guava:guava" } }

        it "has the right version" do
          expect(dependency.version).to eq("33.0.0-jre")
        end
      end
    end

    context "with Seq-style declarations" do
      let(:buildfile_fixture_name) { "seq_build.sbt" }

      its(:length) { is_expected.to eq(5) }

      it "parses all dependencies in the Seq block" do
        expect(dependencies.map(&:name)).to contain_exactly(
          "org.typelevel:cats-core_2.13",
          "com.typesafe.akka:akka-actor_2.13",
          "com.google.guava:guava",
          "org.scalatest:scalatest_2.13",
          "org.scala-lang:scala-library"
        )
      end
    end

    context "with plugins.sbt" do
      let(:plugins_sbt) do
        Dependabot::DependencyFile.new(
          name: "project/plugins.sbt",
          content: fixture("buildfiles", "plugins.sbt")
        )
      end

      let(:dependency_files) { [build_sbt, plugins_sbt] }

      it "parses plugin dependencies" do
        plugin_deps = dependencies.select { |d| d.requirements.any? { |r| r[:groups].include?("plugins") } }
        expect(plugin_deps.length).to eq(2)
      end

      describe "a plugin dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "com.eed3si9n:sbt-assembly" } }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("2.1.5")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.1.5",
              file: "project/plugins.sbt",
              source: nil,
              groups: ["plugins"],
              metadata: nil
            }]
          )
        end
      end
    end

    context "with build.properties" do
      let(:build_properties) do
        Dependabot::DependencyFile.new(
          name: "project/build.properties",
          content: fixture("buildfiles", "build.properties")
        )
      end

      let(:dependency_files) { [build_sbt, build_properties] }

      it "parses the SBT version as a dependency" do
        sbt_dep = dependencies.find { |d| d.name == "org.scala-sbt:sbt" }
        expect(sbt_dep).to be_a(Dependabot::Dependency)
        expect(sbt_dep.version).to eq("1.9.8")
        expect(sbt_dep.requirements).to eq(
          [{
            requirement: "1.9.8",
            file: "project/build.properties",
            source: nil,
            groups: [],
            metadata: { property_source: "build.properties" }
          }]
        )
      end
    end

    context "with Scala 3 cross-versioning" do
      let(:buildfile_fixture_name) { "scala3_build.sbt" }

      its(:length) { is_expected.to eq(3) }

      describe "a cross-versioned Scala 3 dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.typelevel:cats-core_3" } }

        it "uses Scala 3 major version suffix" do
          expect(dependency.name).to eq("org.typelevel:cats-core_3")
        end
      end

      describe "the Scala 3 language dependency" do
        subject(:dependency) { dependencies.find { |d| d.name == "org.scala-lang:scala3-library_3" } }

        it "uses the scala3-library artifact" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("3.3.1")
        end
      end
    end

    context "with comments in the build file" do
      let(:buildfile_fixture_name) { "commented_build.sbt" }

      its(:length) { is_expected.to eq(3) }

      it "ignores commented-out dependencies" do
        dep_names = dependencies.map(&:name)
        expect(dep_names).to include("com.google.guava:guava")
        expect(dep_names).to include("org.typelevel:cats-core_2.13")
        expect(dep_names).not_to include("org.fake:not-real")
      end
    end
  end

  describe "check_required_files" do
    context "when build.sbt is missing" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "project/build.properties",
            content: "sbt.version=1.9.8"
          )
        ]
      end

      it "raises an error" do
        expect { parser }.to raise_error("No build.sbt!")
      end
    end
  end

  describe "ecosystem" do
    it "returns an Ecosystem object" do
      ecosystem = parser.ecosystem
      expect(ecosystem).to be_a(Dependabot::Ecosystem)
      expect(ecosystem.name).to eq("sbt")
    end

    it "has a package manager" do
      pm = parser.ecosystem.package_manager
      expect(pm).to be_a(Dependabot::Sbt::PackageManager)
      expect(pm.name).to eq("sbt")
    end
  end

  context "with project/*.scala build definition files" do
    let(:buildfile_fixture_name) { "scala_file_vals_build.sbt" }

    let(:scala_build_file) do
      Dependabot::DependencyFile.new(
        name: "project/Dependencies.scala",
        content: fixture("buildfiles", "project/Dependencies.scala")
      )
    end

    let(:dependency_files) { [build_sbt, scala_build_file] }

    it "resolves val references from project/*.scala files" do
      dependencies = parser.parse
      cats_dep = dependencies.find { |d| d.name == "org.typelevel:cats-core_2.13" }
      expect(cats_dep).to be_a(Dependabot::Dependency)
      expect(cats_dep.version).to eq("2.10.0")
      expect(cats_dep.requirements.first[:metadata]).to include(
        property_name: "catsVersion",
        property_source: "project/Dependencies.scala"
      )
    end
  end
end
