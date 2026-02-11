# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers/julia"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers::Julia do
  let(:checker) do
    described_class.new(
      source: source,
      credentials: credentials,
      requirements: requirements,
      current_version: current_version
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
    {
      type: "additional_dependency",
      language: "julia",
      hook_id: "julia-lint",
      hook_repo: "https://github.com/example/julia-lint",
      package_name: "JSON",
      original_name: "JSON",
      original_string: "JSON@0.21.4"
    }
  end

  let(:requirements) do
    [{
      requirement: "0.21.4",
      groups: ["additional_dependencies"],
      file: ".pre-commit-config.yaml",
      source: source
    }]
  end

  let(:current_version) { "0.21.4" }

  let(:versions_toml) do
    <<~TOML
      ["0.21.3"]
      git-tree-sha1 = "abc123"

      ["0.21.4"]
      git-tree-sha1 = "def456"

      ["1.0.0"]
      git-tree-sha1 = "ghi789"

      ["1.4.0"]
      git-tree-sha1 = "jkl012"
    TOML
  end

  let(:registry_url) do
    "https://raw.githubusercontent.com/JuliaRegistries/General/master/J/JSON/Versions.toml"
  end

  describe "#latest_version" do
    before do
      stub_request(:get, registry_url).to_return(status: 200, body: versions_toml)
    end

    it "fetches the latest version from the General registry" do
      expect(checker.latest_version).to eq("1.4.0")
    end

    it "requests the correct registry URL" do
      checker.latest_version
      expect(WebMock).to have_requested(:get, registry_url)
    end

    context "when the package has yanked versions" do
      let(:versions_toml) do
        <<~TOML
          ["1.0.0"]
          git-tree-sha1 = "abc123"

          ["2.0.0"]
          git-tree-sha1 = "def456"
          yanked = true

          ["1.5.0"]
          git-tree-sha1 = "ghi789"
        TOML
      end

      it "skips yanked versions" do
        expect(checker.latest_version).to eq("1.5.0")
      end
    end

    context "when the registry returns 404" do
      before do
        stub_request(:get, registry_url).to_return(status: 404)
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the registry is unreachable" do
      before do
        stub_request(:get, registry_url).to_raise(Excon::Error::Socket.new(StandardError.new("Connection refused")))
      end

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when package_name is missing from source" do
      let(:source) { { type: "additional_dependency", language: "julia" } }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    context "with exact version (no operator)" do
      it "updates to the new exact version" do
        updated = checker.updated_requirements("0.22.0")
        expect(updated.first[:requirement]).to eq("0.22.0")
        expect(updated.first[:source][:original_string]).to eq("JSON@0.22.0")
      end
    end

    context "with caret range (^)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "julia",
          hook_id: "julia-format",
          hook_repo: "https://github.com/example/julia-format",
          package_name: "JuliaFormatter",
          original_name: "JuliaFormatter",
          original_string: "JuliaFormatter@^1.0.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "^1.0.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ^ operator" do
        updated = checker.updated_requirements("1.1.0")
        expect(updated.first[:requirement]).to eq("^1.1.0")
        expect(updated.first[:source][:original_string]).to eq("JuliaFormatter@^1.1.0")
      end
    end

    context "with tilde range (~)" do
      let(:source) do
        {
          type: "additional_dependency",
          language: "julia",
          hook_id: "julia-format",
          hook_repo: "https://github.com/example/julia-format",
          package_name: "CSTParser",
          original_name: "CSTParser",
          original_string: "CSTParser@~3.3.0"
        }
      end

      let(:requirements) do
        [{
          requirement: "~3.3.0",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: source
        }]
      end

      it "preserves the ~ operator" do
        updated = checker.updated_requirements("3.4.0")
        expect(updated.first[:requirement]).to eq("~3.4.0")
        expect(updated.first[:source][:original_string]).to eq("CSTParser@~3.4.0")
      end
    end

    it "preserves all requirement properties" do
      updated = checker.updated_requirements("0.22.0")
      expect(updated.first[:groups]).to eq(["additional_dependencies"])
      expect(updated.first[:file]).to eq(".pre-commit-config.yaml")
      expect(updated.first[:source][:type]).to eq("additional_dependency")
      expect(updated.first[:source][:language]).to eq("julia")
      expect(updated.first[:source][:hook_id]).to eq("julia-lint")
      expect(updated.first[:source][:hook_repo]).to eq("https://github.com/example/julia-lint")
      expect(updated.first[:source][:package_name]).to eq("JSON")
    end
  end
end
