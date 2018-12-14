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
      version: "0.5.0-SNAPSHOT",
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
        updated_files.find { |f| f.name == "build.gradle" }
      end

      its(:content) do
        is_expected.to include(
          "compile group: 'co.aikar', name: 'acf-paper', version: "\
          "'0.6.0-SNAPSHOT', changing: true"
        )
      end
      its(:content) { is_expected.to include "version: '4.2.0'" }

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
              requirements: [
                {
                  file: "build.gradle",
                  requirement: "0.6.0-SNAPSHOT",
                  groups: [],
                  source: nil,
                  metadata: nil
                },
                {
                  file: "app/build.gradle",
                  requirement: "0.6.0-SNAPSHOT",
                  groups: [],
                  source: nil,
                  metadata: nil
                }
              ],
              previous_requirements: [
                {
                  file: "build.gradle",
                  requirement: "0.5.0-SNAPSHOT",
                  groups: [],
                  source: nil,
                  metadata: nil
                },
                {
                  file: "app/build.gradle",
                  requirement: "0.5.0-SNAPSHOT",
                  groups: [],
                  source: nil,
                  metadata: nil
                }
              ],
              package_manager: "gradle"
            )
          end

          describe "the build.gradle file" do
            its(:content) do
              is_expected.to include(
                "compile group: 'co.aikar', name: 'acf-paper', version: "\
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
                "compile group: 'co.aikar', name: 'acf-paper', version: "\
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
  end
end
