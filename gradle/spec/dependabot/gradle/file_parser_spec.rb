# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/gradle/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Gradle::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(19) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("co.aikar:acf-paper")
        expect(dependency.version).to eq("0.5.0-SNAPSHOT")
        expect(dependency.requirements).to eq(
          [{
            requirement: "0.5.0-SNAPSHOT",
            file: "build.gradle",
            groups: [],
            source: nil,
            metadata: nil
          }]
        )
      end
    end

    context "specified in short form" do
      let(:buildfile_fixture_name) { "shortform_build.gradle" }

      its(:length) { is_expected.to eq(9) }

      it "handles packaging types" do
        expect(dependencies.map(&:name)).
          to include("com.sparkjava:spark-core")

        dep = dependencies.find { |d| d.name == "com.sparkjava:spark-core" }
        expect(dep.version).to eq("2.5.4")
      end

      it "includes property dependencies" do
        expect(dependencies.map(&:name)).
          to include("org.jetbrains.kotlin:kotlin-stdlib-jre8")
      end

      describe "the property dependency" do
        subject(:dependency) do
          dependencies.find do |dep|
            dep.name == "org.jetbrains.kotlin:kotlin-stdlib-jre8"
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.jetbrains.kotlin:kotlin-stdlib-jre8")
          expect(dependency.version).to eq("1.1.4-3")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.1.4-3",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: { property_name: "kotlin_version" }
            }]
          )
        end
      end

      describe "the git dependency" do
        subject(:dependency) do
          dependencies.find do |dep|
            dep.name == "com.github.heremaps:oksse"
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("com.github.heremaps:oksse")
          expect(dependency.version).to eq(
            "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7"
          )
          expect(dependency.requirements).to eq(
            [{
              requirement: "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7",
              file: "build.gradle",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/heremaps/oksse",
                branch: nil,
                ref: "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7"
              },
              metadata: nil
            }]
          )
        end
      end

      describe "the non-git github.com dependency" do
        subject(:dependency) do
          dependencies.find do |dep|
            dep.name == "com.github.salomonbrys.kotson:kotson"
          end
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("com.github.salomonbrys.kotson:kotson")
          expect(dependency.version).to eq("2.5.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.5.0",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      context "when the name uses a property" do
        let(:buildfile_fixture_name) { "name_property.gradle" }

        it "includes the property dependency" do
          expect(dependencies.map(&:name)).
            to include("org.jetbrains.kotlin:kotlin-stdlib-jre8")
        end
      end
    end

    context "with a version using two properties" do
      let(:buildfile_fixture_name) { "concatenated_properties.gradle" }

      its(:length) { is_expected.to eq(8) }

      it "excludes the dependency with the missing property" do
        expect(dependencies.map(&:name)).
          to_not include("org.scala-lang:scala-library")
      end
    end

    context "with a missing property" do
      let(:buildfile_fixture_name) { "missing_property.gradle" }

      its(:length) { is_expected.to eq(8) }

      it "excludes the dependency with the missing property" do
        expect(dependencies.map(&:name)).
          to_not include("org.gradle:gradle-tooling-api")
      end
    end

    context "with an import" do
      let(:buildfile_fixture_name) { "with_import_build.gradle" }

      # Really we're testing that this parses at all
      its(:length) { is_expected.to eq(4) }
    end

    context "with a dependencyVerification section" do
      let(:buildfile_fixture_name) { "gradle_witness.gradle" }

      # Really we're testing this doesn't include all the verification lines
      its(:length) { is_expected.to eq(34) }
    end

    context "specified in a dependencySet" do
      let(:buildfile_fixture_name) { "dependency_set.gradle" }

      its(:length) { is_expected.to eq(21) }

      describe "a dependencySet dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "io.grpc:grpc-netty" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("io.grpc:grpc-netty")
          expect(dependency.version).to eq("1.15.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.15.1",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: {
                dependency_set: {
                  group: "io.grpc",
                  version: "1.15.1"
                }
              }
            }]
          )
        end
      end

      describe "a plugin dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "org.springframework.boot" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.springframework.boot")
          expect(dependency.version).to eq("2.0.5.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "2.0.5.RELEASE",
              file: "build.gradle",
              groups: ["plugins"],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    context "specified as implementations" do
      let(:buildfile_fixture_name) { "android_build.gradle" }

      its(:length) { is_expected.to eq(24) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("com.google.zxing:core")
          expect(dependency.version).to eq("3.3.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "3.3.0",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    context "with a nested constraint" do
      let(:buildfile_fixture_name) { "nested_constraint_build.gradle" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.springframework:spring-web")
          expect(dependency.version).to eq("5.0.2.RELEASE")
          expect(dependency.requirements).to eq(
            [{
              requirement: "5.0.2.RELEASE",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    context "various different specifications" do
      let(:buildfile_fixture_name) { "duck_duck_go_build.gradle" }

      its(:length) { is_expected.to eq(37) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("com.squareup.leakcanary:leakcanary-android")
          expect(dependency.version).to eq("1.5.4")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.4",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      describe "the repeated dependency" do
        subject(:dependency) do
          dependencies.
            find { |d| d.name == "com.nhaarman:mockito-kotlin-kt1.1" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("com.nhaarman:mockito-kotlin-kt1.1")
          expect(dependency.version).to eq("1.5.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.5.0",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    context "with multiple buildfiles" do
      let(:files) { [buildfile, subproject_buildfile] }
      let(:subproject_buildfile) do
        Dependabot::DependencyFile.new(
          name: "app/build.gradle",
          content: fixture("buildfiles", buildfile_fixture_name)
        )
      end

      its(:length) { is_expected.to eq(19) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("co.aikar:acf-paper")
          expect(dependency.version).to eq("0.5.0-SNAPSHOT")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.5.0-SNAPSHOT",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }, {
              requirement: "0.5.0-SNAPSHOT",
              file: "app/build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    context "with a script plugin" do
      let(:files) { [buildfile, script_plugin] }
      let(:buildfile_fixture_name) { "with_dependency_script.gradle" }
      let(:script_plugin) do
        Dependabot::DependencyFile.new(
          name: "gradle/dependencies.gradle",
          content: fixture("script_plugins", "dependencies.gradle")
        )
      end

      its(:length) { is_expected.to eq(20) }

      describe "the last dependency" do
        subject(:dependency) { dependencies.last }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).
            to eq("org.jetbrains.kotlinx:kotlinx-coroutines-core")
          expect(dependency.version).to eq("0.19.3")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.19.3",
              file: "gradle/dependencies.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }, {
              requirement: "0.26.1-eap13",
              file: "gradle/dependencies.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end
    end

    describe "settings script" do
      let(:files) { [buildfile, settings_file] }
      let(:settings_file) do
        Dependabot::DependencyFile.new(
          name: "settings.gradle",
          content: fixture("settings_files", settings_file_fixture_name)
        )
      end
      let(:settings_file_fixture_name) { "buildscript_dependencies_settings.gradle" }

      subject(:dependencies) { parser.parse }

      its(:length) { is_expected.to eq(20) }
    end

    context "with kotlin" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.gradle.kts",
          content: fixture("buildfiles", buildfile_fixture_name)
        )
      end
      let(:buildfile_fixture_name) { "build.gradle.kts" }

      its(:length) { is_expected.to eq(19) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("co.aikar:acf-paper")
          expect(dependency.version).to eq("0.5.0-SNAPSHOT")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.5.0-SNAPSHOT",
              file: "build.gradle.kts",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      context "specified in short form" do
        let(:buildfile_fixture_name) { "root_build.gradle.kts" }

        its(:length) { is_expected.to eq(33) }

        it "handles packaging types" do
          expect(dependencies.map(&:name)).
            to include("com.sparkjava:spark-core")

          dep = dependencies.find { |d| d.name == "com.sparkjava:spark-core" }
          expect(dep.version).to eq("2.5.4")
        end

        it "includes property dependencies" do
          expect(dependencies.map(&:name)).
            to include("org.jetbrains.kotlin:kotlin-stdlib-jre8")
        end

        describe "the property dependency" do
          subject(:dependency) do
            dependencies.find do |dep|
              dep.name == "org.jetbrains.kotlin:kotlin-stdlib-jre8"
            end
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("org.jetbrains.kotlin:kotlin-stdlib-jre8")
            expect(dependency.version).to eq("1.2.61")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.2.61",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: { property_name: "kotlinVersion" }
              }]
            )
          end
        end

        describe "the git dependency" do
          subject(:dependency) do
            dependencies.find do |dep|
              dep.name == "com.github.heremaps:oksse"
            end
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("com.github.heremaps:oksse")
            expect(dependency.version).to eq(
              "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7"
            )
            expect(dependency.requirements).to eq(
              [{
                requirement: "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7",
                file: "build.gradle.kts",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/heremaps/oksse",
                  branch: nil,
                  ref: "be5d2cd6deb8cf3ca2c9a740bdacec816871d4f7"
                },
                metadata: nil
              }]
            )
          end
        end

        describe "the non-git github.com dependency" do
          subject(:dependency) do
            dependencies.find do |dep|
              dep.name == "com.github.salomonbrys.kotson:kotson"
            end
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("com.github.salomonbrys.kotson:kotson")
            expect(dependency.version).to eq("2.5.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "2.5.0",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }]
            )
          end
        end
      end

      context "specified in a dependencySet" do
        let(:buildfile_fixture_name) { "root_build.gradle.kts" }

        its(:length) { is_expected.to eq(33) }

        describe "a dependencySet dependency" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "io.grpc:grpc-netty" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("io.grpc:grpc-netty")
            expect(dependency.version).to eq("1.15.1")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.15.1",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: {
                  dependency_set: {
                    group: "io.grpc",
                    version: "1.15.1"
                  }
                }
              }]
            )
          end
        end

        describe "a plugin dependency" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "org.springframework.boot" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("org.springframework.boot")
            expect(dependency.version).to eq("2.0.5.RELEASE")
            expect(dependency.requirements).to eq(
              [{
                requirement: "2.0.5.RELEASE",
                file: "build.gradle.kts",
                groups: ["plugins"],
                source: nil,
                metadata: nil
              }]
            )
          end
        end

        describe "a plugin kotlin dependency" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "jvm" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("jvm")
            expect(dependency.version).to eq("1.3.72")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.3.72",
                file: "build.gradle.kts",
                groups: %w(plugins kotlin),
                source: nil,
                metadata: nil
              }]
            )
          end
        end

        describe "a plugin dependency using a version variable" do
          subject(:dependency) do
            dependencies.find { |d| d.name == "org.unbroken-dome.helm" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("org.unbroken-dome.helm")
            expect(dependency.version).to eq("1.6.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.6.0",
                file: "build.gradle.kts",
                groups: %w(plugins),
                source: nil,
                metadata: { property_name: "helmVersion" }
              }]
            )
          end
        end
      end

      context "various different specifications" do
        let(:buildfile_fixture_name) { "duck_duck_go_build.gradle.kts" }

        its(:length) { is_expected.to eq(37) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("com.squareup.leakcanary:leakcanary-android")
            expect(dependency.version).to eq("1.5.4")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.5.4",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }]
            )
          end
        end

        describe "the repeated dependency" do
          subject(:dependency) do
            dependencies.
              find { |d| d.name == "com.nhaarman:mockito-kotlin-kt1.1" }
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("com.nhaarman:mockito-kotlin-kt1.1")
            expect(dependency.version).to eq("1.5.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "1.5.0",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }]
            )
          end
        end
      end

      context "with multiple buildfiles" do
        let(:files) { [buildfile, subproject_buildfile] }
        let(:subproject_buildfile) do
          Dependabot::DependencyFile.new(
            name: "app/build.gradle.kts",
            content: fixture("buildfiles", buildfile_fixture_name)
          )
        end

        its(:length) { is_expected.to eq(19) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("co.aikar:acf-paper")
            expect(dependency.version).to eq("0.5.0-SNAPSHOT")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.5.0-SNAPSHOT",
                file: "build.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }, {
                requirement: "0.5.0-SNAPSHOT",
                file: "app/build.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }]
            )
          end
        end
      end

      context "with a script plugin" do
        let(:files) { [buildfile, script_plugin] }
        let(:buildfile_fixture_name) { "root_build.gradle.kts" }
        let(:script_plugin) do
          Dependabot::DependencyFile.new(
            name: "gradle/dependencies.gradle.kts",
            content: fixture("script_plugins", "dependencies.gradle.kts")
          )
        end

        its(:length) { is_expected.to eq(42) }

        describe "the last dependency" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).
              to eq("org.jetbrains.kotlinx:kotlinx-coroutines-core")
            expect(dependency.version).to eq("0.19.3")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.19.3",
                file: "gradle/dependencies.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }, {
                requirement: "0.26.1-eap13",
                file: "gradle/dependencies.gradle.kts",
                groups: [],
                source: nil,
                metadata: nil
              }]
            )
          end
        end
      end

      describe "kotlin settings script" do
        let(:files) { [buildfile, settings_file] }
        let(:settings_file) do
          Dependabot::DependencyFile.new(
            name: "settings.gradle.kts",
            content: fixture("settings_files", settings_file_fixture_name)
          )
        end
        let(:settings_file_fixture_name) { "buildscript_dependencies_settings.gradle.kts" }

        subject(:dependencies) { parser.parse }

        its(:length) { is_expected.to eq(20) }
      end
    end

    describe "with a version catalog file" do
      let(:files) { [buildfile, version_catalog] }
      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          content: fixture("version_catalog_file", "libs.versions.toml")
        )
      end

      its(:length) { is_expected.to eq(33) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("co.aikar:acf-paper")
          expect(dependency.version).to eq("0.5.0-SNAPSHOT")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.5.0-SNAPSHOT",
              file: "build.gradle",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      describe "dependency with explicit module and referenced version" do
        let(:dependency) do
          dependencies.find { |dep| dep.name == "androidx.test.espresso:espresso-core" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("3.5.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "3.5.0",
              file: "gradle/libs.versions.toml",
              groups: [],
              source: nil,
              metadata: { property_name: "espresso" }
            }]
          )
        end
      end

      describe "dependency with group + name and referenced version" do
        let(:dependency) do
          dependencies.find { |dep| dep.name == "org.jetbrains.kotlin:kotlin-gradle-plugin" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("1.7.20")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.7.20",
              file: "gradle/libs.versions.toml",
              groups: [],
              source: nil,
              metadata: { property_name: "kotlin" }
            }]
          )
        end
      end

      describe "plugin with explicit module and referenced version" do
        let(:dependency) do
          dependencies.find { |dep| dep.name == "org.jlleitschuh.gradle.ktlint" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.version).to eq("9.0.0")
          expect(dependency.requirements).to eq(
            [{
              requirement: "10.0.0",
              file: "gradle/libs.versions.toml",
              groups: ["plugins"],
              source: nil,
              metadata: { property_name: "ktlint" }
            }, {
              requirement: "9.0.0",
              file: "gradle/libs.versions.toml",
              groups: ["plugins"],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      describe "non-referenced version dependency" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "androidx.activity:activity-compose" }
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("androidx.activity:activity-compose")
          expect(dependency.version).to eq("1.3.1")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.3.1",
              file: "gradle/libs.versions.toml",
              groups: [],
              source: nil,
              metadata: nil
            }]
          )
        end
      end

      describe "rich version dependency is ignored" do
        subject(:dependency) do
          dependencies.find { |d| d.name == "androidx.compose.material:material" }
        end
        it "has the right details" do
          expect(dependency).to be(nil)
        end
      end

      context "with version catalog file containing dependency overlap with build file" do
        let(:files) { [buildfile, version_catalog_overlap] }

        let(:version_catalog_overlap) do
          Dependabot::DependencyFile.new(
            name: "gradle/libs.versions.toml",
            content: fixture("version_catalog_file", "libs.versions.overlapping.toml")
          )
        end

        its(:length) { is_expected.to eq(31) }

        describe "the first dependency" do
          subject(:dependency) { dependencies.first }

          # This test is wrong,  req should also contain changes in the version catalog file
          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("co.aikar:acf-paper")
            expect(dependency.version).to eq("0.5.0-SNAPSHOT")
            expect(dependency.requirements).to eq(
              [{
                requirement: "0.5.0-SNAPSHOT",
                file: "build.gradle",
                groups: [],
                source: nil,
                metadata: nil
              },
               {
                 requirement: "0.5.0-SNAPSHOT",
                 file: "gradle/libs.versions.toml",
                 groups: [],
                 source: nil,
                 metadata: { property_name: "coAikar" }
               }]
            )
          end
        end

        describe "the last library dependency" do
          subject(:dependency) { dependencies[-2] }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("androidx.test.espresso:espresso-core")
            expect(dependency.version).to eq("3.5.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "3.5.0",
                file: "gradle/libs.versions.toml",
                groups: [],
                source: nil,
                metadata: { property_name: "espresso" }
              }]
            )
          end
        end

        describe "the version catalog plugin" do
          subject(:dependency) { dependencies.last }

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("org.jmailen.kotlinter")
            expect(dependency.version).to eq("3.11.0")
            expect(dependency.requirements).to eq(
              [{
                requirement: "3.11.0",
                file: "gradle/libs.versions.toml",
                groups: ["plugins"],
                source: nil,
                metadata: nil
              }]
            )
          end
        end
      end
    end

    describe "parse only version catalog file that contains only libraries" do
      let(:files) { [version_catalog] }
      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          content: fixture("version_catalog_file", "libs.versions.only.libraries.toml")
        )
      end

      its(:length) { is_expected.to eq(11) }
    end

    describe "parse only version catalog file that contains only plugins" do
      let(:files) { [version_catalog] }
      let(:version_catalog) do
        Dependabot::DependencyFile.new(
          name: "gradle/libs.versions.toml",
          content: fixture("version_catalog_file", "libs.versions.only.plugins.toml")
        )
      end

      its(:length) { is_expected.to eq(2) }
    end
  end
end
