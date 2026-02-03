# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_parser"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyParser do
  describe ".parse" do
    let(:hook_id) { "mypy" }
    let(:repo_url) { "https://github.com/pre-commit/mirrors-mypy" }
    let(:file_name) { ".pre-commit-config.yaml" }

    context "with Python dependencies" do
      let(:language) { "python" }

      context "with a simple pinned dependency" do
        let(:dep_string) { "types-requests==2.28.11.5" }

        it "parses the dependency correctly" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          expect(result.name).to eq("#{repo_url}::#{hook_id}::types-requests")
          expect(result.version).to eq("2.28.11.5")
          expect(result.package_manager).to eq("pre_commit")

          source = result.requirements.first[:source]
          expect(source[:type]).to eq("additional_dependency")
          expect(source[:language]).to eq("python")
          expect(source[:registry]).to eq("pypi")
          expect(source[:package_name]).to eq("types-requests")
          expect(source[:hook_id]).to eq("mypy")
          expect(source[:original_string]).to eq("types-requests==2.28.11.5")
        end
      end

      context "with a dependency with extras" do
        let(:dep_string) { "click[testing]==8.1.3" }

        it "parses the dependency including extras" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          expect(result.name).to eq("#{repo_url}::#{hook_id}::click")
          expect(result.version).to eq("8.1.3")

          source = result.requirements.first[:source]
          expect(source[:extras]).to eq("testing")
          expect(source[:original_string]).to eq("click[testing]==8.1.3")
        end
      end

      context "with a dependency with multiple extras" do
        let(:dep_string) { "package[extra1,extra2]==1.0.0" }

        it "parses multiple extras" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          source = result.requirements.first[:source]
          expect(source[:extras]).to eq("extra1,extra2")
        end
      end

      context "with a version range (>=, <)" do
        let(:dep_string) { "pydantic>=1.10,<2.0" }

        it "extracts the lower bound version" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          expect(result.version).to eq("1.10")
          expect(result.requirements.first[:requirement]).to eq(">=1.10,<2.0")
        end
      end

      context "with a compatible release (~=)" do
        let(:dep_string) { "requests~=2.28.0" }

        it "extracts the version from compatible release" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          expect(result.version).to eq("2.28.0")
        end
      end

      context "with only upper bound (<)" do
        let(:dep_string) { "pydantic<2.0" }

        it "returns nil (no lower bound to use as current version)" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_nil
        end
      end

      context "with a dependency without version" do
        let(:dep_string) { "requests" }

        it "returns nil (no version to update)" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_nil
        end
      end

      context "with normalized package names" do
        let(:dep_string) { "Types_Requests==2.28.11.5" }

        it "normalizes the package name" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          # Name should be normalized (lowercase, dashes)
          expect(result.name).to include("types-requests")

          source = result.requirements.first[:source]
          expect(source[:package_name]).to eq("types-requests")
          expect(source[:original_name]).to eq("Types_Requests")
        end
      end

      context "with pre-release version" do
        let(:dep_string) { "pydantic==2.0.0a1" }

        it "parses pre-release versions" do
          result = described_class.parse(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            language: language,
            file_name: file_name
          )

          expect(result).to be_a(Dependabot::Dependency)
          expect(result.version).to eq("2.0.0a1")
        end
      end

      context "with operator preservation" do
        context "with exact pin (==)" do
          let(:dep_string) { "requests==2.28.0" }

          it "stores == as the operator" do
            result = described_class.parse(
              dep_string: dep_string,
              hook_id: hook_id,
              repo_url: repo_url,
              language: language,
              file_name: file_name
            )

            source = result.requirements.first[:source]
            expect(source[:operator]).to eq("==")
          end
        end

        context "with greater-than-or-equal (>=)" do
          let(:dep_string) { "requests>=2.28.0" }

          it "stores >= as the operator" do
            result = described_class.parse(
              dep_string: dep_string,
              hook_id: hook_id,
              repo_url: repo_url,
              language: language,
              file_name: file_name
            )

            source = result.requirements.first[:source]
            expect(source[:operator]).to eq(">=")
          end
        end

        context "with compatible release (~=)" do
          let(:dep_string) { "requests~=2.28.0" }

          it "stores ~= as the operator (converted back from Ruby's ~>)" do
            result = described_class.parse(
              dep_string: dep_string,
              hook_id: hook_id,
              repo_url: repo_url,
              language: language,
              file_name: file_name
            )

            source = result.requirements.first[:source]
            expect(source[:operator]).to eq("~=")
          end
        end

        context "with range (>=, <)" do
          let(:dep_string) { "requests>=2.28.0,<3.0.0" }

          it "stores >= as the operator (from lower bound)" do
            result = described_class.parse(
              dep_string: dep_string,
              hook_id: hook_id,
              repo_url: repo_url,
              language: language,
              file_name: file_name
            )

            source = result.requirements.first[:source]
            expect(source[:operator]).to eq(">=")
          end
        end
      end
    end

    context "with Node.js dependencies" do
      let(:language) { "node" }
      let(:dep_string) { "eslint@8.35.0" }

      it "returns nil (not yet implemented)" do
        result = described_class.parse(
          dep_string: dep_string,
          hook_id: hook_id,
          repo_url: repo_url,
          language: language,
          file_name: file_name
        )

        expect(result).to be_nil
      end
    end

    context "with unsupported language" do
      let(:language) { "haskell" }
      let(:dep_string) { "some-package:1.0.0" }

      it "returns nil" do
        result = described_class.parse(
          dep_string: dep_string,
          hook_id: hook_id,
          repo_url: repo_url,
          language: language,
          file_name: file_name
        )

        expect(result).to be_nil
      end
    end
  end

  describe ".supported_language?" do
    it "returns true for supported languages" do
      expect(described_class.supported_language?("python")).to be true
      expect(described_class.supported_language?("node")).to be true
      expect(described_class.supported_language?("golang")).to be true
      expect(described_class.supported_language?("rust")).to be true
      expect(described_class.supported_language?("ruby")).to be true
    end

    it "returns false for unsupported languages" do
      expect(described_class.supported_language?("haskell")).to be false
      expect(described_class.supported_language?("julia")).to be false
      expect(described_class.supported_language?("unknown")).to be false
    end

    it "handles case-insensitive matching" do
      expect(described_class.supported_language?("Python")).to be true
      expect(described_class.supported_language?("PYTHON")).to be true
    end
  end
end
