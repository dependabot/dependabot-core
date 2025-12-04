# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn"
require "dependabot/dependency_graphers"

RSpec.describe Dependabot::NpmAndYarn::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("npm_and_yarn").new(
      file_parser: parser
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("npm_and_yarn").new(
      dependency_files: dependency_files,
      repo_contents_path: nil,
      source: source,
      credentials: credentials
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/npm-project",
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

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
  end

  describe "#relevant_dependency_file" do
    context "when a lockfile exists" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

      it "returns the lockfile" do
        expect(grapher.relevant_dependency_file.name).to eq("package-lock.json")
      end
    end

    context "when no lockfile exists" do
      let(:dependency_files) { project_dependency_files("grapher/npm_exact_versions_no_lockfile") }

      before do
        # Mock lockfile generation to avoid network calls
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "returns the package.json" do
        expect(grapher.relevant_dependency_file.name).to eq("package.json")
      end
    end
  end

  describe "#resolved_dependencies" do
    context "with a lockfile present" do
      let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

      it "correctly serializes the resolved dependencies" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.count).to be >= 1

        is_number = resolved_dependencies["pkg:npm/is-number@7.0.0"]
        expect(is_number).not_to be_nil
        expect(is_number.package_url).to eq("pkg:npm/is-number@7.0.0")
        expect(is_number.direct).to be(true)
        expect(is_number.runtime).to be(true)
      end
    end

    context "without a lockfile - exact versions" do
      let(:dependency_files) { project_dependency_files("grapher/npm_exact_versions_no_lockfile") }

      before do
        # Mock lockfile generation to avoid network calls
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "includes dependencies with exact versions from package.json" do
        resolved_dependencies = grapher.resolved_dependencies

        # With exact versions (no lockfile), the parser can still extract versions
        lodash = resolved_dependencies["pkg:npm/lodash@4.17.21"]
        expect(lodash).not_to be_nil
        expect(lodash.package_url).to eq("pkg:npm/lodash@4.17.21")
        expect(lodash.direct).to be(true)
      end
    end

    context "without a lockfile - range versions" do
      let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

      before do
        # Mock lockfile generation to avoid network calls
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "emits a warning about missing lockfile" do
        allow(Dependabot.logger).to receive(:info) # Allow other info logs
        expect(Dependabot.logger).to receive(:info).with(/No lockfile found/)
        expect(Dependabot.logger).to receive(:warn).with(/No lockfile was found/)

        grapher.resolved_dependencies
      end
    end
  end

  describe "package manager detection" do
    context "with npm project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "npm@10.0.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects npm as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("npm")
      end
    end

    context "with yarn project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "yarn@3.6.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects yarn as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("yarn")
      end
    end

    context "with pnpm project (packageManager field)" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "packageManager" => "pnpm@8.6.0",
          "dependencies" => { "lodash" => "4.17.21" }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          )
        ]
      end

      before do
        lockfile_generator = instance_double(
          Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator,
          generate: nil
        )
        allow(Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator)
          .to receive(:new).and_return(lockfile_generator)
      end

      it "detects pnpm as the package manager" do
        expect(grapher.send(:detected_package_manager)).to eq("pnpm")
      end
    end
  end

  describe "purl generation" do
    let(:dependency_files) { project_dependency_files("grapher/npm_with_lockfile") }

    it "uses 'npm' as the purl type" do
      resolved_dependencies = grapher.resolved_dependencies

      resolved_dependencies.each_key do |purl|
        expect(purl).to start_with("pkg:npm/")
      end
    end

    context "with scoped packages" do
      let(:package_json_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "dependencies" => { "@scope/package" => "1.0.0" }
        }.to_json
      end

      let(:package_lock_content) do
        {
          "name" => "test",
          "version" => "1.0.0",
          "lockfileVersion" => 3,
          "packages" => {
            "" => {
              "name" => "test",
              "version" => "1.0.0",
              "dependencies" => { "@scope/package" => "1.0.0" }
            },
            "node_modules/@scope/package" => {
              "version" => "1.0.0",
              "resolved" => "https://registry.npmjs.org/@scope/package/-/package-1.0.0.tgz"
            }
          }
        }.to_json
      end

      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: package_json_content,
            directory: "/"
          ),
          Dependabot::DependencyFile.new(
            name: "package-lock.json",
            content: package_lock_content,
            directory: "/"
          )
        ]
      end

      it "URL-encodes the @ symbol in scoped package names" do
        resolved_dependencies = grapher.resolved_dependencies

        scoped_purl = resolved_dependencies.keys.find { |k| k.include?("scope") }
        expect(scoped_purl).to include("%40scope/package")
      end
    end
  end

  describe "registration" do
    it "is registered as the grapher for npm_and_yarn" do
      grapher_class = Dependabot::DependencyGraphers.for_package_manager("npm_and_yarn")
      expect(grapher_class).to eq(described_class)
    end
  end
end
