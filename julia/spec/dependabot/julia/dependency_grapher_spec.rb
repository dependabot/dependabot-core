# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules"

RSpec.describe Dependabot::Julia::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("julia").new(
      file_parser: parser
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("julia").new(
      dependency_files:,
      repo_contents_path: "/",
      source: source,
      credentials: [],
      reject_external_code: false
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot/dependabot-cli",
      directory: "/",
      branch: "main"
    )
  end

  let(:dependency_files) { [project_file, manifest_file].compact }

  context "with a typical project" do
    let(:project_file) do
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: fixture("projects", "basic", "Project.toml")
      )
    end

    let(:manifest_file) do
      Dependabot::DependencyFile.new(
        name: "Manifest.toml",
        content: fixture("projects", "basic", "Manifest.toml")
      )
    end

    describe "#relevant_dependency_file" do
      it "specifies the Project.toml as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(project_file)
      end
    end

    describe "#resolved_dependencies" do
      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be(1)

        expect(resolved_dependencies.keys).to eql(
          %w(
            Example
          )
        )

        # Direct dependencies
        example = resolved_dependencies["Example"]
        expect(example.package_url).to eql("pkg:generic/Example@0.4")
        expect(example.direct).to be(true)
        expect(example.runtime).to be(true)
      end
    end
  end

  context "without a manifest file" do
    let(:project_file) do
      Dependabot::DependencyFile.new(
        name: "Project.toml",
        content: fixture("projects", "basic", "Project.toml")
      )
    end

    let(:manifest_file) do
      nil
    end

    describe "#relevant_dependency_file" do
      it "specifies the Project.toml as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(project_file)
      end
    end

    describe "#resolved_dependencies" do
      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be(1)

        expect(resolved_dependencies.keys).to eql(
          %w(
            Example
          )
        )

        # Direct dependencies
        example = resolved_dependencies["Example"]
        expect(example.package_url).to eql("pkg:generic/Example@0.4")
        expect(example.direct).to be(true)
        expect(example.runtime).to be(true)
      end
    end
  end
end
