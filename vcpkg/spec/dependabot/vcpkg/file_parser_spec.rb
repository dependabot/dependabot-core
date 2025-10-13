# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency_file"
require "dependabot/source"

require "dependabot/vcpkg"
require "dependabot/vcpkg/file_parser"

require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Vcpkg::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "microsoft/vcpkg",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: dependency_files, source: source) }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    context "with a valid vcpkg.json file" do
      let(:dependency_files) { [vcpkg_json] }
      let(:vcpkg_json) do
        Dependabot::DependencyFile.new(
          name: "vcpkg.json",
          content: vcpkg_json_content
        )
      end

      context "when vcpkg.json contains a builtin-baseline" do
        let(:vcpkg_json_content) do
          <<~JSON
            {
              "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
              "builtin-baseline": "fe1cde61e971d53c9687cf9a46308f8f55da19fa",
              "dependencies": [
                "fmt",
                "ms-gsl"
              ]
            }
          JSON
        end

        it "returns a single dependency for the vcpkg baseline" do
          expect(dependencies.length).to eq(1)
        end

        describe "the parsed dependency" do
          subject(:dependency) { dependencies.first }

          it "has the correct attributes" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("github.com/microsoft/vcpkg")
            expect(dependency.version).to eq("fe1cde61e971d53c9687cf9a46308f8f55da19fa")
            expect(dependency.package_manager).to eq("vcpkg")
            expect(dependency.requirements).to eq(
              [{
                file: "vcpkg.json",
                requirement: nil,
                groups: [],
                source: {
                  type: "git",
                  url: Dependabot::Vcpkg::VCPKG_DEFAULT_BASELINE_URL,
                  ref: "master"
                }
              }]
            )
          end
        end
      end

      context "when vcpkg.json contains dependencies with version constraints" do
        let(:vcpkg_json_content) do
          <<~JSON
            {
              "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
              "builtin-baseline": "fe1cde61e971d53c9687cf9a46308f8f55da19fa",
              "dependencies": [
                "curl",
                {
                  "name": "openssl",
                  "version>=": "3.1"
                },
                {
                  "name": "zlib",
                  "version>=": "1.2.11#3"
                }
              ]
            }
          JSON
        end

        it "returns the baseline dependency and dependencies with version constraints" do
          expect(dependencies.length).to eq(3)

          baseline_dep = dependencies.find { |d| d.name == "github.com/microsoft/vcpkg" }
          expect(baseline_dep).not_to be_nil

          openssl_dep = dependencies.find { |d| d.name == "openssl" }
          expect(openssl_dep).not_to be_nil
          expect(openssl_dep.version).to eq("3.1")
          expect(openssl_dep.requirements.first[:requirement]).to eq(">=3.1")

          zlib_dep = dependencies.find { |d| d.name == "zlib" }
          expect(zlib_dep).not_to be_nil
          expect(zlib_dep.version).to eq("1.2.11")
          expect(zlib_dep.requirements.first[:requirement]).to eq(">=1.2.11#3")
        end

        it "logs warnings for dependencies without version constraints" do
          expect(Dependabot.logger)
            .to receive(:warn).with("Skipping vcpkg dependency 'curl' without version>= constraint")
          dependencies
        end
      end

      context "when vcpkg.json contains only dependencies with version constraints" do
        let(:vcpkg_json_content) do
          <<~JSON
            {
              "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
              "dependencies": [
                {
                  "name": "openssl",
                  "version>=": "3.1"
                }
              ]
            }
          JSON
        end

        it "returns only the dependency with version constraint" do
          expect(dependencies.length).to eq(1)

          openssl_dep = dependencies.first
          expect(openssl_dep.name).to eq("openssl")
          expect(openssl_dep.version).to eq("3.1")
          expect(openssl_dep.package_manager).to eq("vcpkg")
          expect(openssl_dep.requirements).to eq(
            [{
              file: "vcpkg.json",
              requirement: ">=3.1",
              groups: [],
              source: nil
            }]
          )
        end
      end

      context "when vcpkg.json contains only string dependencies" do
        let(:vcpkg_json_content) do
          <<~JSON
            {
              "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
              "dependencies": [
                "curl",
                "openssl"
              ]
            }
          JSON
        end

        it "returns no dependencies and logs warnings" do
          expect(Dependabot.logger)
            .to receive(:warn)
            .with("Skipping vcpkg dependency 'curl' without version>= constraint")
          expect(Dependabot.logger)
            .to receive(:warn)
            .with("Skipping vcpkg dependency 'openssl' without version>= constraint")
          expect(dependencies).to be_empty
        end
      end

      context "when vcpkg.json does not contain a builtin-baseline" do
        let(:vcpkg_json_content) do
          <<~JSON
            {
              "$schema": "https://raw.githubusercontent.com/microsoft/vcpkg-tool/main/docs/vcpkg.schema.json",
              "dependencies": [
                "fmt",
                "ms-gsl"
              ]
            }
          JSON
        end

        it "returns no dependencies" do
          expect(dependencies).to be_empty
        end
      end

      context "when vcpkg.json is empty" do
        let(:vcpkg_json_content) { "{}" }

        it "returns no dependencies" do
          expect(dependencies).to be_empty
        end
      end

      context "when vcpkg.json has invalid JSON" do
        let(:vcpkg_json_content) { "{ invalid json" }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("vcpkg.json")
          end
        end
      end

      context "when vcpkg.json has null content" do
        let(:vcpkg_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg.json",
            content: nil
          )
        end

        it "returns no dependencies" do
          expect(dependencies).to be_empty
        end
      end
    end

    context "with a vcpkg-configuration.json file" do
      let(:dependency_files) { [vcpkg_json, vcpkg_configuration_json] }
      let(:vcpkg_json) do
        Dependabot::DependencyFile.new(
          name: "vcpkg.json",
          content: <<~JSON
            {
              "builtin-baseline": "fe1cde61e971d53c9687cf9a46308f8f55da19fa"
            }
          JSON
        )
      end
      let(:vcpkg_configuration_json) do
        Dependabot::DependencyFile.new(
          name: "vcpkg-configuration.json",
          content: <<~JSON
            {
              "default-registry": {
                "kind": "git",
                "repository": "https://github.com/microsoft/vcpkg",
                "baseline": "fe1cde61e971d53c9687cf9a46308f8f55da19fa"
              }
            }
          JSON
        )
      end

      it "parses both vcpkg.json and vcpkg-configuration.json" do
        expect(dependencies.length).to eq(2)

        # First dependency should be from vcpkg.json builtin-baseline
        builtin_dependency = dependencies.find { |d| d.name == "github.com/microsoft/vcpkg" }
        expect(builtin_dependency).not_to be_nil
        expect(builtin_dependency.version).to eq("fe1cde61e971d53c9687cf9a46308f8f55da19fa")
        expect(builtin_dependency.requirements.first[:file]).to eq("vcpkg.json")

        # Second dependency should be from vcpkg-configuration.json default-registry
        registry_dependency = dependencies.find { |d| d.name == "https://github.com/microsoft/vcpkg" }
        expect(registry_dependency).not_to be_nil
        expect(registry_dependency.version).to eq("fe1cde61e971d53c9687cf9a46308f8f55da19fa")
        expect(registry_dependency.requirements.first[:file]).to eq("vcpkg-configuration.json")
        expect(registry_dependency.requirements.first[:source][:url]).to eq("https://github.com/microsoft/vcpkg")
      end
    end

    context "with a vcpkg-configuration.json file containing different registry types" do
      let(:dependency_files) { [vcpkg_configuration_json] }

      context "with builtin registry as default-registry" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "default-registry": {
                  "kind": "builtin",
                  "baseline": "abc123def456789012345678901234567890abcd"
                }
              }
            JSON
          )
        end

        it "parses builtin default-registry" do
          expect(dependencies.length).to eq(1)

          dependency = dependencies.first
          expect(dependency.name).to eq("github.com/microsoft/vcpkg")
          expect(dependency.version).to eq("abc123def456789012345678901234567890abcd")
          expect(dependency.package_manager).to eq("vcpkg")
          expect(dependency.requirements.first[:file]).to eq("vcpkg-configuration.json")
          expect(dependency.requirements.first[:source][:type]).to eq("git")
          expect(dependency.requirements.first[:source][:url]).to eq("https://github.com/microsoft/vcpkg.git")
          expect(dependency.requirements.first[:source][:ref]).to eq("master")
        end
      end

      context "with git registries in the registries array" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "registries": [
                  {
                    "kind": "git",
                    "repository": "https://github.com/custom/registry",
                    "baseline": "123abc456def789012345678901234567890abcd",
                    "reference": "main",
                    "packages": ["custom-*"]
                  },
                  {
                    "kind": "builtin",
                    "baseline": "def456789012345678901234567890abcd123abc",
                    "packages": ["boost-*"]
                  }
                ]
              }
            JSON
          )
        end

        it "parses multiple registries" do
          expect(dependencies.length).to eq(2)

          git_registry = dependencies.find { |d| d.name.include?("custom/registry") }
          expect(git_registry).not_to be_nil
          expect(git_registry.name).to eq("https://github.com/custom/registry")
          expect(git_registry.version).to eq("123abc456def789012345678901234567890abcd")
          expect(git_registry.requirements.first[:source][:url]).to eq("https://github.com/custom/registry")
          expect(git_registry.requirements.first[:source][:ref]).to eq("main")

          builtin_registry = dependencies.find { |d| d.name.include?("microsoft/vcpkg") }
          expect(builtin_registry).not_to be_nil
          expect(builtin_registry.name).to eq("github.com/microsoft/vcpkg")
          expect(builtin_registry.version).to eq("def456789012345678901234567890abcd123abc")
          expect(builtin_registry.requirements.first[:source][:url]).to eq("https://github.com/microsoft/vcpkg.git")
        end
      end

      context "with filesystem registry (should be ignored)" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "default-registry": {
                  "kind": "filesystem",
                  "path": "/local/path/to/registry",
                  "baseline": "default"
                }
              }
            JSON
          )
        end

        it "ignores filesystem registries" do
          expect(dependencies).to be_empty
        end
      end

      context "with missing baseline (should be ignored)" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "default-registry": {
                  "kind": "git",
                  "repository": "https://github.com/custom/registry"
                }
              }
            JSON
          )
        end

        it "ignores registries without baseline" do
          expect(dependencies).to be_empty
        end
      end

      context "with missing repository for git registry (should be ignored)" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "default-registry": {
                  "kind": "git",
                  "baseline": "abc123def456789012345678901234567890abcd"
                }
              }
            JSON
          )
        end

        it "ignores git registries without repository" do
          expect(dependencies).to be_empty
        end
      end

      context "with mixed supported and non-supported registries" do
        let(:vcpkg_configuration_json) do
          Dependabot::DependencyFile.new(
            name: "vcpkg-configuration.json",
            content: <<~JSON
              {
                "default-registry": {
                  "kind": "git",
                  "repository": "https://github.com/custom/registry",
                  "baseline": "abc123def456789012345678901234567890abcd"
                },
                "registries": [
                  {
                    "kind": "filesystem",
                    "path": "/local/path",
                    "baseline": "default",
                    "packages": ["local-*"]
                  },
                  {
                    "kind": "git",
                    "repository": "https://github.com/another/registry",
                    "baseline": "def456789012345678901234567890abcd123abc",
                    "packages": ["another-*"]
                  }
                ]
              }
            JSON
          )
        end

        it "only tracks git and builtin registries" do
          expect(dependencies.length).to eq(2)

          default_registry = dependencies.find { |d| d.name.include?("custom/registry") }
          expect(default_registry).not_to be_nil
          expect(default_registry.name).to eq("https://github.com/custom/registry")

          git_registry = dependencies.find { |d| d.name.include?("another/registry") }
          expect(git_registry).not_to be_nil
          expect(git_registry.name).to eq("https://github.com/another/registry")
        end
      end
    end

    context "without required files" do
      let(:dependency_files) { [other_file] }
      let(:other_file) do
        Dependabot::DependencyFile.new(
          name: "README.md",
          content: "# Test project"
        )
      end

      it "raises a DependencyFileNotFound error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotFound, "No vcpkg manifest files found")
      end
    end

    context "with empty dependency files array" do
      let(:dependency_files) { [] }

      it "raises a DependencyFileNotFound error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotFound, "No vcpkg manifest files found")
      end
    end
  end

  describe "#check_required_files" do
    subject(:check_required_files) { parser.send(:check_required_files) }

    context "when vcpkg.json is present" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "vcpkg.json", content: "{}")]
      end

      it "does not raise an error" do
        expect { check_required_files }.not_to raise_error
      end
    end

    context "when vcpkg.json is not present" do
      let(:dependency_files) do
        [Dependabot::DependencyFile.new(name: "other.json", content: "{}")]
      end

      it "raises a DependencyFileNotFound error" do
        expect do
          check_required_files
        end.to raise_error(Dependabot::DependencyFileNotFound, "No vcpkg manifest files found")
      end
    end
  end
end
