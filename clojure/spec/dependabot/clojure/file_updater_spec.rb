# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clojure/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Clojure::FileUpdater do
  let(:updater) do
    described_class.new(dependency_files: files, dependencies: [dependency], credentials: [])
  end
  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "lein" }
  let(:original) { files.find { |f| f.name == file_name }.content }
  let(:file_name) { "project.clj" }

  def requirement(file, version, groups)
    { file: file, requirement: version, groups: groups, source: nil }
  end

  def updated_content(name = file_name)
    updater.updated_dependency_files.find { |f| f.name == name }.content
  end

  it_behaves_like "a dependency file updater"

  context "with a dependency declared at the top level and in a profile" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "ring:ring-core",
        version: "1.12.2",
        previous_version: "1.9.6",
        requirements: [
          requirement("project.clj", "1.12.2", ["dependencies"]),
          requirement("project.clj", "1.12.2", ["profile:dev"])
        ],
        previous_requirements: [
          requirement("project.clj", "1.9.6", ["dependencies"]),
          requirement("project.clj", "1.9.6", ["profile:dev"])
        ],
        package_manager: "clojure"
      )
    end

    it "updates both declarations and nothing else" do
      expect(updated_content).to eq(
        original
          .sub('[ring/ring-core "1.9.6" :exclusions', '[ring/ring-core "1.12.2" :exclusions')
          .sub('[ring/ring-core "1.9.6"]]}', '[ring/ring-core "1.12.2"]]}')
      )
    end
  end

  context "when only the profile declaration changes" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "ring:ring-core",
        version: "1.9.6",
        previous_version: "1.9.6",
        requirements: [
          requirement("project.clj", "1.9.6", ["dependencies"]),
          requirement("project.clj", "1.12.2", ["profile:dev"])
        ],
        previous_requirements: [
          requirement("project.clj", "1.9.6", ["dependencies"]),
          requirement("project.clj", "1.9.6", ["profile:dev"])
        ],
        package_manager: "clojure"
      )
    end

    it "leaves the top-level declaration alone" do
      expect(updated_content).to eq(original.sub('[ring/ring-core "1.9.6"]]}', '[ring/ring-core "1.12.2"]]}'))
    end
  end

  context "with a deps.edn alias dependency" do
    let(:project_name) { "deps" }
    let(:file_name) { "deps.edn" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "lambdaisland:kaocha",
        version: "1.91.1392",
        previous_version: "1.87.1366",
        requirements: [requirement("deps.edn", "1.91.1392", ["alias:test"])],
        previous_requirements: [requirement("deps.edn", "1.87.1366", ["alias:test"])],
        package_manager: "clojure"
      )
    end

    it "updates the version string" do
      expect(updated_content).to eq(original.sub('"1.87.1366"', '"1.91.1392"'))
    end
  end

  context "with an emoji before the version on the same line" do
    let(:files) do
      [Dependabot::DependencyFile.new(
        name: "project.clj",
        content: %((defproject x "1" :description "🚀 app" :dependencies [[ring "1.0"]])\n)
      )]
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "ring:ring",
        version: "2.0",
        previous_version: "1.0",
        requirements: [requirement("project.clj", "2.0", ["dependencies"])],
        previous_requirements: [requirement("project.clj", "1.0", ["dependencies"])],
        package_manager: "clojure"
      )
    end

    it "finds the right position" do
      expect(updated_content).to eq(original.sub('"1.0"', '"2.0"'))
    end
  end

  context "with a dependency in both a project.clj and a deps.edn" do
    let(:project_name) { "lein_and_deps" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "cheshire:cheshire",
        version: "6.0.0",
        previous_version: "5.11.0",
        requirements: [
          requirement("project.clj", "6.0.0", ["dependencies"]),
          requirement("deps.edn", "6.0.0", ["dependencies"])
        ],
        previous_requirements: [
          requirement("project.clj", "5.11.0", ["dependencies"]),
          requirement("deps.edn", "5.11.0", ["dependencies"])
        ],
        package_manager: "clojure"
      )
    end

    it "updates both files" do
      expect(updated_content("project.clj")).to include('[cheshire "6.0.0"]')
      expect(updated_content("deps.edn")).to include('cheshire/cheshire {:mvn/version "6.0.0"}')
    end
  end
end
