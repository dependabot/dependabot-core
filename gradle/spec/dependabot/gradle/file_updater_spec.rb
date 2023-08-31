# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/gradle/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Gradle::FileUpdater do
  it_behaves_like "a dependency file updater"

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
  let(:dependency_files) { [buildfile] }
  let(:dependencies) { [dependency] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "co.aikar:acf-paper",
      version: "0.6.0-SNAPSHOT",
      requirements: [{
        file: "build.gradle",
        requirement: "0.6.0-SNAPSHOT",
        groups: [],
        source: nil,
        metadata: nil
      }],
      previous_requirements: [{
        file: "build.gradle",
        requirement: "0.5.0-SNAPSHOT",
        groups: [],
        source: nil,
        metadata: nil
      }],
      package_manager: "gradle"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated build.gradle file" do
      subject(:updated_buildfile) do
        updated_files.find do |f|
          Dependabot::Gradle::FileUpdater::SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
        end
      end

      its(:content) do
        is_expected.to include(
          "compile group: 'co.aikar', name: 'acf-paper', version: " \
          "'0.6.0-SNAPSHOT', changing: true"
        )
      end
      its(:content) { is_expected.to include "version: '4.2.0'" }

      context "with kotlin" do
        let(:buildfile_fixture_name) { "build.gradle.kts" }

        its(:content) do
          is_expected.to include(
            'implementation(group = "co.aikar", name = "acf-paper", version = "0.6.0-SNAPSHOT", changing: true)'
          )
        end
        its(:content) { is_expected.to include 'version = "4.2.0"' }
      end

      context "with a plugin" do
        let(:buildfile_fixture_name) { "dependency_set.gradle" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.springframework.boot",
            version: "2.1.4.RELEASE",
            requirements: [{
              file: "build.gradle",
              requirement: "2.1.4.RELEASE",
              groups: ["plugins"],
              source: nil,
              metadata: nil
            }],
            previous_requirements: [{
              file: "build.gradle",
              requirement: "2.0.5.RELEASE",
              groups: ["plugins"],
              source: nil,
              metadata: nil
            }],
            package_manager: "gradle"
          )
        end

        its(:content) do
          is_expected.to include(
            'id "org.springframework.boot" version "2.1.4.RELEASE" apply false'
          )
        end

        context "with kotlin" do
          let(:buildfile_fixture_name) { "root_build.gradle.kts" }

          its(:content) do
            is_expected.to include(
              'id("org.springframework.boot") version "2.1.4.RELEASE" apply false'
            )
          end

          context "with a dependency version defined by a property" do
            let(:buildfile) do
              Dependabot::DependencyFile.new(
                name: "build.gradle.kts",
                content: fixture("buildfiles", buildfile_fixture_name)
              )
            end
            let(:dependencies) do
              [
                Dependabot::Dependency.new(
                  name: "org.jetbrains.kotlin:kotlin-gradle-plugin",
                  version: "23.6-jre",
                  previous_version: "1.2.61",
                  requirements: [{
                    file: "build.gradle.kts",
                    requirement: "23.6-jre",
                    groups: [],
                    source: {
                      type: "maven_repo",
                      url: "https://repo.maven.apache.org/maven2"
                    },
                    metadata: { property_name: "kotlinVersion" }
                  }],
                  previous_requirements: [{
                    file: "build.gradle.kts",
                    requirement: "1.2.61",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "kotlinVersion" }
                  }],
                  package_manager: "gradle"
                ),
                Dependabot::Dependency.new(
                  name: "org.jetbrains.kotlin:kotlin-stdlib-jre8",
                  version: "23.6-jre",
                  previous_version: "1.2.61",
                  requirements: [{
                    file: "build.gradle.kts",
                    requirement: "23.6-jre",
                    groups: [],
                    source: {
                      type: "maven_repo",
                      url: "https://repo.maven.apache.org/maven2"
                    },
                    metadata: { property_name: "kotlinVersion" }
                  }],
                  previous_requirements: [{
                    file: "build.gradle.kts",
                    requirement: "1.2.61",
                    groups: [],
                    source: nil,
                    metadata: { property_name: "kotlinVersion" }
                  }],
                  package_manager: "gradle"
                )
              ]
            end

            it "updates the version in the build.gradle.kts" do
              expect(updated_files.map(&:name)).to eq(["build.gradle.kts"])
              expect(updated_files.first.content).
                to include('extra["kotlinVersion"] = "23.6-jre"')
            end
          end
        end

        context "with a kotlin plugin" do
          let(:buildfile_fixture_name) { "root_build.gradle.kts" }
          let(:buildfile) do
            Dependabot::DependencyFile.new(
              name: "build.gradle.kts",
              content: fixture("buildfiles", buildfile_fixture_name)
            )
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "jvm",
              version: "1.4.21-2",
              requirements: [{
                file: "build.gradle.kts",
                requirement: "1.4.21-2",
                groups: %w(plugins kotlin),
                source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
                metadata: nil
              }],
              previous_requirements: [{
                file: "build.gradle.kts",
                requirement: "1.3.72",
                groups: %w(plugins kotlin),
                source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
                metadata: nil
              }],
              package_manager: "gradle"
            )
          end

          its(:content) do
            is_expected.to include(
              'kotlin("jvm") version "1.4.21-2"'
            )
          end
        end
      end

      context "with multiple buildfiles" do
        let(:dependency_files) { [buildfile, subproject_buildfile] }
        let(:subproject_buildfile) do
          Dependabot::DependencyFile.new(
            name: "app/build.gradle",
            content: fixture("buildfiles", buildfile_fixture_name)
          )
        end

        context "when only one file is affected" do
          specify { expect(updated_files.count).to eq(1) }
        end

        context "when both buildfiles are affected" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "co.aikar:acf-paper",
              version: "0.5.0-SNAPSHOT",
              requirements: [{
                file: "build.gradle",
                requirement: "0.6.0-SNAPSHOT",
                groups: [],
                source: nil,
                metadata: nil
              }, {
                file: "app/build.gradle",
                requirement: "0.6.0-SNAPSHOT",
                groups: [],
                source: nil,
                metadata: nil
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "0.5.0-SNAPSHOT",
                groups: [],
                source: nil,
                metadata: nil
              }, {
                file: "app/build.gradle",
                requirement: "0.5.0-SNAPSHOT",
                groups: [],
                source: nil,
                metadata: nil
              }],
              package_manager: "gradle"
            )
          end

          describe "the build.gradle file" do
            its(:content) do
              is_expected.to include(
                "compile group: 'co.aikar', name: 'acf-paper', version: " \
                "'0.6.0-SNAPSHOT', changing: true"
              )
            end
            its(:content) { is_expected.to include "version: '4.2.0'" }
          end

          describe "the app/build.gradle file" do
            subject(:updated_buildfile) do
              updated_files.find { |f| f.name == "app/build.gradle" }
            end

            its(:content) do
              is_expected.to include(
                "compile group: 'co.aikar', name: 'acf-paper', version: " \
                "'0.6.0-SNAPSHOT', changing: true"
              )
            end
            its(:content) { is_expected.to include "version: '4.2.0'" }
          end
        end
      end

      context "with a dependency name defined by a property" do
        let(:buildfile_fixture_name) { "name_property.gradle" }

        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.jetbrains.kotlin:kotlin-stdlib-jre8",
              version: "23.6-jre",
              previous_version: "1.1.4-3",
              requirements: [{
                file: "build.gradle",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                }
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "1.1.4-3",
                groups: [],
                source: nil
              }],
              package_manager: "gradle"
            )
          ]
        end

        it "updates the version in the build.gradle" do
          expect(updated_buildfile.content).
            to include('compile "org.jetbrains.kotlin:$name_prop:23.6-jre"')
        end
      end

      context "with multiple configurations using the same dependency" do
        let(:buildfile_fixture_name) { "multiple_configurations.gradle" }

        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.projectlombok:lombok",
              version: "1.18.26",
              previous_version: "1.18.24",
              requirements: [{
                file: "build.gradle",
                requirement: "1.18.26",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                }
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "1.18.24",
                groups: [],
                source: nil
              }],
              package_manager: "gradle"
            )
          ]
        end

        it "updates the version in all configurations" do
          expect(updated_buildfile.content).
            to include("compileOnly 'org.projectlombok:lombok:1.18.26'").
            and include("annotationProcessor 'org.projectlombok:lombok:1.18.26'")
        end
      end

      context "with a dependency version defined by a property" do
        let(:dependency_files) { [buildfile, subproject_buildfile] }
        let(:subproject_buildfile) do
          Dependabot::DependencyFile.new(
            name: "subproject/build.gradle",
            content:
              fixture("buildfiles", subproject_fixture_name)
          )
        end

        let(:buildfile_fixture_name) { "basic_build.gradle" }
        let(:subproject_fixture_name) { "shortform_build.gradle" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.jetbrains.kotlin:kotlin-gradle-plugin",
              version: "23.6-jre",
              previous_version: "1.1.4-3",
              requirements: [{
                file: "subproject/build.gradle",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: { property_name: "kotlin_version" }
              }],
              previous_requirements: [{
                file: "subproject/build.gradle",
                requirement: "1.1.4-3",
                groups: [],
                source: nil,
                metadata: { property_name: "kotlin_version" }
              }],
              package_manager: "gradle"
            ),
            Dependabot::Dependency.new(
              name: "org.jetbrains.kotlin:kotlin-stdlib-jre8",
              version: "23.6-jre",
              previous_version: "1.1.4-3",
              requirements: [{
                file: "subproject/build.gradle",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://repo.maven.apache.org/maven2"
                },
                metadata: { property_name: "kotlin_version" }
              }],
              previous_requirements: [{
                file: "subproject/build.gradle",
                requirement: "1.1.4-3",
                groups: [],
                source: nil,
                metadata: { property_name: "kotlin_version" }
              }],
              package_manager: "gradle"
            )
          ]
        end

        it "updates the version in the subproject/build.gradle" do
          expect(updated_files.map(&:name)).to eq(["subproject/build.gradle"])
          expect(updated_files.first.content).
            to include("ext.kotlin_version = '23.6-jre'")
        end

        context "that is inherited from the parent buildfile" do
          let(:buildfile_fixture_name) { "shortform_build.gradle" }
          let(:subproject_fixture_name) { "inherited_property.gradle" }

          it "updates the version in the build.gradle" do
            expect(updated_files.map(&:name)).to eq(["build.gradle"])
            expect(updated_files.first.content).
              to include("ext.kotlin_version = '23.6-jre'")
          end
        end
      end

      context "with a dependency from a dependency set" do
        let(:buildfile_fixture_name) { "dependency_set.gradle" }
        let(:dependencies) do
          %w(
            com.google.protobuf:protoc
            com.google.protobuf:protobuf-java
            com.google.protobuf:protobuf-java-util
          ).map do |dep_name|
            Dependabot::Dependency.new(
              name: dep_name,
              version: "23.6-jre",
              previous_version: "3.6.1",
              requirements: [{
                file: "build.gradle",
                requirement: "23.6-jre",
                groups: [],
                source: {
                  type: "maven_repo",
                  url: "https://jcenter.bintray.com"
                },
                metadata: {
                  dependency_set: {
                    group: "com.google.protobuf",
                    version: "3.6.1"
                  }
                }
              }],
              previous_requirements: [{
                file: "build.gradle",
                requirement: "3.6.1",
                groups: [],
                source: nil,
                metadata: {
                  dependency_set: {
                    group: "com.google.protobuf",
                    version: "3.6.1"
                  }
                }
              }],
              package_manager: "gradle"
            )
          end
        end

        it "updates the version in the dependency set declaration" do
          expect(updated_files.map(&:name)).to eq(["build.gradle"])
          expect(updated_files.first.content).
            to include(
              "endencySet(group: 'com.google.protobuf', version: '23.6-jre') {"
            )
          expect(updated_files.first.content).
            to include("dependency 'org.apache.kafka:kafka-clients:3.6.1'")
        end
      end
    end

    context "when updating a script plugin" do
      let(:dependency_files) { [buildfile, script_plugin] }
      let(:buildfile_fixture_name) { "with_dependency_script.gradle" }
      let(:script_plugin) do
        Dependabot::DependencyFile.new(
          name: "gradle/dependencies.gradle",
          content: fixture("script_plugins", "dependencies.gradle")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "org.jetbrains.kotlinx:kotlinx-coroutines-core",
          version: "1.1.1",
          previous_version: "0.19.3",
          requirements: [{
            requirement: "1.1.1",
            file: "gradle/dependencies.gradle",
            groups: [],
            source: { type: "maven_repo", url: "https://jcenter.bintray.com" },
            metadata: nil
          }, {
            requirement: "1.1.1",
            file: "gradle/dependencies.gradle",
            groups: [],
            source: { type: "maven_repo", url: "https://jcenter.bintray.com" },
            metadata: nil
          }],
          previous_requirements: [{
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
          }],
          package_manager: "gradle"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated plugin script file" do
        subject(:updated_buildfile) do
          updated_files.find { |f| f.name == "gradle/dependencies.gradle" }
        end

        its(:content) do
          is_expected.
            to include("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.1.1")
        end
      end

      context "with a version catalog" do
        let(:buildfile) do
          Dependabot::DependencyFile.new(
            name: "gradle/libs.versions.toml",
            content: fixture("version_catalog_file", "libs.versions.toml")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.jmailen.kotlinter",
            version: "3.12.0",
            previous_version: "3.10.0",
            requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "3.12.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: nil
            }],
            previous_requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "3.10.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: nil
            }],
            package_manager: "gradle"
          )
        end

        subject(:updated_buildfile) do
          updated_files.find { |f| f.name == "gradle/libs.versions.toml" }
        end
        its(:content) do
          is_expected.to include(
            'kotlinter = { id = "org.jmailen.kotlinter", version = "3.12.0" }'
          )
        end
      end
      context "with a version catalog with ref" do
        let(:buildfile) do
          Dependabot::DependencyFile.new(
            name: "gradle/libs.versions.toml",
            content: fixture("version_catalog_file", "libs.versions.toml")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.jlleitschuh.gradle.ktlint",
            version: "11.0.0",
            previous_version: "10.0.0",
            requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "11.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: { property_name: "ktlint" }
            }],
            previous_requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "10.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: { property_name: "ktlint" }
            }],
            package_manager: "gradle"
          )
        end

        subject(:updated_buildfile) do
          updated_files.find { |f| f.name == "gradle/libs.versions.toml" }
        end
        its(:content) do
          is_expected.to include(
            'ktlint = "11.0.0"'
          )
        end
      end

      context "with a version catalog with ref and non-ref mixed" do
        let(:buildfile) do
          Dependabot::DependencyFile.new(
            name: "gradle/libs.versions.toml",
            content: fixture("version_catalog_file", "libs.versions.toml")
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.jlleitschuh.gradle.ktlint",
            version: "11.0.0",
            previous_version: "9.0.0",
            requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "11.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: { property_name: "ktlint" }
            }, {
              file: "gradle/libs.versions.toml",
              requirement: "11.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: nil
            }],
            previous_requirements: [{
              file: "gradle/libs.versions.toml",
              requirement: "10.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: { property_name: "ktlint" }
            }, {
              file: "gradle/libs.versions.toml",
              requirement: "9.0.0",
              groups: ["plugins"],
              source: { type: "maven_repo", url: "https://plugins.gradle.org/m2" },
              metadata: nil
            }],
            package_manager: "gradle"
          )
        end

        subject(:updated_buildfile) do
          updated_files.find { |f| f.name == "gradle/libs.versions.toml" }
        end
        its(:content) do
          is_expected.to include(
            'ktlint = "11.0.0"'
          )
          is_expected.to include(
            'ktlintUpdated = { id = "org.jlleitschuh.gradle.ktlint", version = "11.0.0" }'
          )
        end
      end
    end
  end
end
