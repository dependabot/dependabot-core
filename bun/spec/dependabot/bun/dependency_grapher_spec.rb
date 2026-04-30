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

    context "with a lockfile containing subdependencies" do
      let(:dependency_files) { project_dependency_files("bun/grapher_with_subdeps") }

      it "includes subdependency edges for direct packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        fetch_factory = resolved_dependencies["pkg:npm/fetch-factory@0.0.1"]
        expect(fetch_factory).not_to be_nil
        expect(fetch_factory.direct).to be(true)
        expect(fetch_factory.dependencies).to contain_exactly(
          "pkg:npm/es6-promise@3.3.1",
          "pkg:npm/isomorphic-fetch@2.2.1",
          "pkg:npm/lodash@3.10.1"
        )
      end

      it "includes subdependency edges for transitive packages with children" do
        resolved_dependencies = grapher.resolved_dependencies

        isomorphic_fetch = resolved_dependencies["pkg:npm/isomorphic-fetch@2.2.1"]
        expect(isomorphic_fetch).not_to be_nil
        expect(isomorphic_fetch.direct).to be(false)
        expect(isomorphic_fetch.dependencies).to contain_exactly(
          "pkg:npm/node-fetch@1.7.3",
          "pkg:npm/whatwg-fetch@3.6.20"
        )
      end

      it "reports leaf packages with empty dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        lodash = resolved_dependencies["pkg:npm/lodash@3.10.1"]
        expect(lodash).not_to be_nil
        expect(lodash.direct).to be(false)
        expect(lodash.dependencies).to eq([])

        safer_buffer = resolved_dependencies["pkg:npm/safer-buffer@2.1.2"]
        expect(safer_buffer).not_to be_nil
        expect(safer_buffer.direct).to be(false)
        expect(safer_buffer.dependencies).to eq([])
      end

      it "correctly resolves deep dependency chains" do
        resolved_dependencies = grapher.resolved_dependencies

        node_fetch = resolved_dependencies["pkg:npm/node-fetch@1.7.3"]
        expect(node_fetch).not_to be_nil
        expect(node_fetch.direct).to be(false)
        expect(node_fetch.dependencies).to contain_exactly(
          "pkg:npm/encoding@0.1.13",
          "pkg:npm/is-stream@1.1.0"
        )
      end
    end

    context "when the lockfile is corrupt" do
      let(:dependency_files) { project_dependency_files("bun/grapher_with_subdeps") }

      before do
        # Pre-populate dependencies via the parser (which reads the valid lockfile)
        grapher.send(:prepare!)
        # Swap in a corrupt lockfile for relationship extraction
        corrupt_lockfile = Dependabot::DependencyFile.new(
          name: "bun.lock", content: "not valid {{{", directory: "/"
        )
        grapher.instance_variable_set(:@lockfile, corrupt_lockfile)
      end

      it "sets the errored_fetching_subdependencies flag" do
        grapher.resolved_dependencies

        expect(grapher.errored_fetching_subdependencies).to be(true)
      end

      it "stores the parse error as subdependency_error" do
        grapher.resolved_dependencies

        expect(grapher.subdependency_error).to be_a(Dependabot::DependencyFileNotParseable)
      end

      it "returns dependencies with empty relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).not_to be_empty
        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end
  end

  describe "registration" do
    it "registers as the grapher for the bun package manager" do
      expect(Dependabot::DependencyGraphers.for_package_manager("bun")).to eq(described_class)
    end
  end
end
