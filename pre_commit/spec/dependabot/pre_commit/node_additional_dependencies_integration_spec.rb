# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/SpecFilePathFormat
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pre_commit/file_parser"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/file_updater"

RSpec.describe Dependabot::PreCommit do
  # rubocop:enable RSpec/SpecFilePathFormat
  context "with Node additional_dependencies integration" do
    let(:file) do
      Dependabot::DependencyFile.new(
        name: ".pre-commit-config.yaml",
        content: fixture("pre_commit_configs", "with_node_additional_dependencies.yaml")
      )
    end

    let(:credentials) do
      [Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )]
    end

    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "dependabot/dependabot-core"
      )
    end

    describe "FileParser" do
      let(:parser) do
        Dependabot::PreCommit::FileParser.new(
          dependency_files: [file],
          source: source,
          credentials: credentials
        )
      end

      it "parses Node additional_dependencies" do
        dependencies = parser.parse

        additional_deps = dependencies.select do |dep|
          dep.requirements.any? { |req| req[:source]&.dig(:type) == "additional_dependency" }
        end

        expect(additional_deps.length).to eq(8)

        eslint = additional_deps.find do |dep|
          dep.requirements.first[:source][:package_name] == "eslint"
        end
        expect(eslint).not_to be_nil
        expect(eslint.version).to eq("4.15.0")
        expect(eslint.requirements.first[:requirement]).to eq("4.15.0")
        expect(eslint.requirements.first[:source][:language]).to eq("node")
        expect(eslint.requirements.first[:source][:hook_id]).to eq("eslint")
        expect(eslint.requirements.first[:source][:original_string]).to eq("eslint@4.15.0")

        scoped = additional_deps.find do |dep|
          dep.requirements.first[:source][:package_name] == "@prettier/plugin-xml"
        end
        expect(scoped).not_to be_nil
        expect(scoped.version).to eq("3.2.0")
        expect(scoped.requirements.first[:source][:original_string]).to eq("@prettier/plugin-xml@3.2.0")

        ts = additional_deps.find do |dep|
          dep.requirements.first[:source][:package_name] == "typescript"
        end
        expect(ts).not_to be_nil
        expect(ts.version).to eq("5.3.0")
        expect(ts.requirements.first[:requirement]).to eq("~5.3.0")

        ts_node = additional_deps.find do |dep|
          dep.requirements.first[:source][:package_name] == "ts-node"
        end
        expect(ts_node).not_to be_nil
        expect(ts_node.version).to eq("10.9.0")
        expect(ts_node.requirements.first[:requirement]).to eq("^10.9.0")
      end
    end

    describe "UpdateChecker" do
      let(:parser) do
        Dependabot::PreCommit::FileParser.new(
          dependency_files: [file],
          source: source,
          credentials: credentials
        )
      end

      let(:dependencies) { parser.parse }

      let(:dependency) do
        dependencies.find do |dep|
          dep.requirements.first[:source]&.dig(:package_name) == "eslint"
        end
      end

      let(:update_checker) do
        Dependabot::PreCommit::UpdateChecker.new(
          dependency: dependency,
          dependency_files: [file],
          credentials: credentials,
          ignored_versions: [],
          security_advisories: [],
          raise_on_ignored: false
        )
      end

      # rubocop:disable RSpec/VerifiedDoubleReference
      let(:npm_checker_class) { class_double("Dependabot::NpmAndYarn::UpdateChecker") }
      # rubocop:enable RSpec/VerifiedDoubleReference
      let(:npm_checker) { instance_double(Dependabot::UpdateCheckers::Base) }
      let(:latest_version_obj) { Gem::Version.new("9.0.0") }

      before do
        allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
          .with("npm_and_yarn")
          .and_return(npm_checker_class)
        allow(npm_checker_class).to receive(:new).and_return(npm_checker)
        allow(npm_checker).to receive(:latest_version).and_return(latest_version_obj)
      end

      it "identifies the dependency as an additional_dependency" do
        expect(update_checker.send(:additional_dependency?)).to be true
      end

      it "delegates to npm_and_yarn UpdateChecker for latest_version" do
        latest = update_checker.latest_version
        expect(latest).to eq("9.0.0")
      end

      it "generates updated requirements with correct format" do
        updated_reqs = update_checker.updated_requirements
        expect(updated_reqs.first[:requirement]).to eq("9.0.0")
        expect(updated_reqs.first[:source][:original_string]).to eq("eslint@9.0.0")
      end
    end

    describe "FileUpdater" do
      let(:parser) do
        Dependabot::PreCommit::FileParser.new(
          dependency_files: [file],
          source: source,
          credentials: credentials
        )
      end

      let(:dependencies) { parser.parse }

      let(:dependency) do
        dependencies.find do |dep|
          dep.requirements.first[:source]&.dig(:package_name) == "eslint"
        end
      end

      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: dependency.name,
          version: "9.0.0",
          previous_version: dependency.version,
          requirements: [{
            requirement: "9.0.0",
            groups: ["additional_dependencies"],
            file: ".pre-commit-config.yaml",
            source: dependency.requirements.first[:source].merge(
              original_string: "eslint@9.0.0"
            )
          }],
          previous_requirements: dependency.requirements,
          package_manager: "pre_commit"
        )
      end

      let(:file_updater) do
        Dependabot::PreCommit::FileUpdater.new(
          dependencies: [updated_dependency],
          dependency_files: [file],
          credentials: credentials
        )
      end

      it "updates the node additional_dependency in the config file" do
        updated_files = file_updater.updated_dependency_files
        expect(updated_files.length).to eq(1)

        updated_content = updated_files.first.content
        expect(updated_content).to include("eslint@9.0.0")
        expect(updated_content).not_to include("eslint@4.15.0")

        expect(updated_content).to include("eslint-config-google@0.7.1")
        expect(updated_content).to include("eslint-plugin-react@6.10.3")
        expect(updated_content).to include("babel-eslint@6.1.2")
      end

      context "when updating a scoped package" do
        let(:dependency) do
          dependencies.find do |dep|
            dep.requirements.first[:source]&.dig(:package_name) == "@prettier/plugin-xml"
          end
        end

        let(:updated_dependency) do
          Dependabot::Dependency.new(
            name: dependency.name,
            version: "3.3.0",
            previous_version: dependency.version,
            requirements: [{
              requirement: "3.3.0",
              groups: ["additional_dependencies"],
              file: ".pre-commit-config.yaml",
              source: dependency.requirements.first[:source].merge(
                original_string: "@prettier/plugin-xml@3.3.0"
              )
            }],
            previous_requirements: dependency.requirements,
            package_manager: "pre_commit"
          )
        end

        it "updates the scoped package correctly" do
          updated_files = file_updater.updated_dependency_files
          updated_content = updated_files.first.content

          expect(updated_content).to include("@prettier/plugin-xml@3.3.0")
          expect(updated_content).not_to include("@prettier/plugin-xml@3.2.0")
        end
      end

      context "when updating a range dependency" do
        let(:dependency) do
          dependencies.find do |dep|
            dep.requirements.first[:source]&.dig(:package_name) == "ts-node"
          end
        end

        let(:updated_dependency) do
          Dependabot::Dependency.new(
            name: dependency.name,
            version: "10.10.0",
            previous_version: dependency.version,
            requirements: [{
              requirement: "^10.10.0",
              groups: ["additional_dependencies"],
              file: ".pre-commit-config.yaml",
              source: dependency.requirements.first[:source].merge(
                original_string: "ts-node@^10.10.0"
              )
            }],
            previous_requirements: dependency.requirements,
            package_manager: "pre_commit"
          )
        end

        it "preserves the range operator in the update" do
          updated_files = file_updater.updated_dependency_files
          updated_content = updated_files.first.content

          expect(updated_content).to include("ts-node@^10.10.0")
          expect(updated_content).not_to include("ts-node@^10.9.0")
        end
      end
    end

    describe "Full workflow" do
      it "can parse, check, and update Node additional_dependencies" do
        parser = Dependabot::PreCommit::FileParser.new(
          dependency_files: [file],
          source: source,
          credentials: credentials
        )
        dependencies = parser.parse

        additional_dep = dependencies.find do |dep|
          dep.requirements.first[:source]&.dig(:package_name) == "eslint"
        end
        expect(additional_dep).not_to be_nil

        npm_checker_class = class_double("Dependabot::NpmAndYarn::UpdateChecker") # rubocop:disable RSpec/VerifiedDoubleReference
        npm_checker = instance_double(Dependabot::UpdateCheckers::Base)
        latest_version_obj = Gem::Version.new("9.0.0")
        allow(Dependabot::UpdateCheckers).to receive(:for_package_manager)
          .with("npm_and_yarn")
          .and_return(npm_checker_class)
        allow(npm_checker_class).to receive(:new).and_return(npm_checker)
        allow(npm_checker).to receive(:latest_version).and_return(latest_version_obj)

        update_checker = Dependabot::PreCommit::UpdateChecker.new(
          dependency: additional_dep,
          dependency_files: [file],
          credentials: credentials,
          ignored_versions: [],
          security_advisories: [],
          raise_on_ignored: false
        )

        latest = update_checker.latest_version
        expect(latest).to eq("9.0.0")

        updated_reqs = update_checker.updated_requirements
        expect(updated_reqs.first[:requirement]).to eq("9.0.0")
        expect(updated_reqs.first[:source][:original_string]).to eq("eslint@9.0.0")

        updated_dep = Dependabot::Dependency.new(
          name: additional_dep.name,
          version: latest,
          previous_version: additional_dep.version,
          requirements: updated_reqs,
          previous_requirements: additional_dep.requirements,
          package_manager: "pre_commit"
        )

        file_updater = Dependabot::PreCommit::FileUpdater.new(
          dependencies: [updated_dep],
          dependency_files: [file],
          credentials: credentials
        )

        updated_files = file_updater.updated_dependency_files
        expect(updated_files.first.content).to include("eslint@9.0.0")
        expect(updated_files.first.content).not_to include("eslint@4.15.0")
      end
    end
  end
end
