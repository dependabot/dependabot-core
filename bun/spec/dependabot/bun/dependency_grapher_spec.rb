# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"
require "dependabot/dependency_graphers"

RSpec.describe Dependabot::Bun::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("bun").new(
      file_parser: parser
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("bun").new(
      dependency_files: dependency_files,
      repo_contents_path: nil,
      source: source,
      credentials: credentials
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/bun-project",
      directory: "/",
      branch: "main"
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )
    ]
  end

  describe "#relevant_dependency_file" do
    context "when a lockfile exists" do
      let(:dependency_files) { project_dependency_files("bun/grapher_with_lockfile") }

      it "returns the bun.lock file" do
        expect(grapher.relevant_dependency_file.name).to eq("bun.lock")
      end
    end

    context "when no lockfile exists" do
      let(:dependency_files) { project_dependency_files("javascript/exact_version_requirements_no_lockfile") }

      it "returns the package.json" do
        expect(grapher.relevant_dependency_file.name).to eq("package.json")
      end
    end
  end

  describe "#resolved_dependencies" do
    context "with a lockfile present" do
      let(:dependency_files) { project_dependency_files("bun/grapher_with_lockfile") }

      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to eq(3)
      end

      it "identifies direct runtime dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.package_url).to eq("pkg:npm/is-number@7.0.0")
        expect(is_number.direct).to be(true)
        expect(is_number.runtime).to be(true)
      end

      it "identifies direct dev dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        etag = resolved_dependencies["pkg:npm/etag@1.8.1"]
        expect(etag).not_to be_nil
        expect(etag.package_url).to eq("pkg:npm/etag@1.8.1")
        expect(etag.direct).to be(true)
        expect(etag.runtime).to be(false)
      end

      it "handles scoped package names in PURLs" do
        resolved_dependencies = grapher.resolved_dependencies

        scoped = resolved_dependencies["pkg:npm/%40scope/package@1.2.0"]
        expect(scoped).not_to be_nil
        expect(scoped.package_url).to eq("pkg:npm/%40scope/package@1.2.0")
        expect(scoped.direct).to be(true)
        expect(scoped.runtime).to be(true)
      end
    end
  end
end
