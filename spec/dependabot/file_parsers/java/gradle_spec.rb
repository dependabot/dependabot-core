# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/gradle"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Java::Gradle do
  it_behaves_like "a dependency file parser"

  let(:files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

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

      its(:length) { is_expected.to eq(8) }

      it "includes property dependencies" do
        expect(dependencies.map(&:name)).
          to include("org.jetbrains.kotlin:kotlin-stdlib-jre8")
      end

      context "the property dependency" do
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
    end

    context "with an import" do
      let(:buildfile_fixture_name) { "with_import_build.gradle" }

      # Really we're testing that this parses at all
      its(:length) { is_expected.to eq(4) }
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

      its(:length) { is_expected.to eq(38) }

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
          content: fixture("java", "buildfiles", buildfile_fixture_name)
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
            [
              {
                requirement: "0.5.0-SNAPSHOT",
                file: "build.gradle",
                groups: [],
                source: nil,
                metadata: nil
              },
              {
                requirement: "0.5.0-SNAPSHOT",
                file: "app/build.gradle",
                groups: [],
                source: nil,
                metadata: nil
              }
            ]
          )
        end
      end
    end
  end
end
