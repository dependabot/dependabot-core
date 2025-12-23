# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/lean/update_checker"

RSpec.describe Dependabot::Lean::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: [],
      security_advisories: []
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
  let(:files) { [lean_toolchain] }
  let(:lean_toolchain) do
    Dependabot::DependencyFile.new(
      name: "lean-toolchain",
      content: "leanprover/lean4:v4.26.0\n"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "lean4",
      version: "4.26.0",
      requirements: [{
        requirement: "4.26.0",
        file: "lean-toolchain",
        groups: [],
        source: { type: "default" }
      }],
      package_manager: "lean"
    )
  end

  let(:github_releases_response) do
    [
      {
        "tag_name" => "v4.28.0",
        "name" => "Lean 4.28.0",
        "published_at" => "2024-12-15T00:00:00Z",
        "prerelease" => false
      },
      {
        "tag_name" => "v4.28.0-rc1",
        "name" => "Lean 4.28.0-rc1",
        "published_at" => "2024-12-10T00:00:00Z",
        "prerelease" => true
      },
      {
        "tag_name" => "v4.27.0",
        "name" => "Lean 4.27.0",
        "published_at" => "2024-11-15T00:00:00Z",
        "prerelease" => false
      },
      {
        "tag_name" => "v4.26.0",
        "name" => "Lean 4.26.0",
        "published_at" => "2024-10-15T00:00:00Z",
        "prerelease" => false
      }
    ]
  end

  before do
    stub_request(:get, "https://api.github.com/repos/leanprover/lean4/releases?page=1&per_page=100")
      .to_return(
        status: 200,
        body: github_releases_response.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#latest_version" do
    it "returns the latest stable version" do
      expect(checker.latest_version).to eq("4.28.0")
    end

    context "when on an RC version" do
      let(:lean_toolchain) do
        Dependabot::DependencyFile.new(
          name: "lean-toolchain",
          content: "leanprover/lean4:v4.27.0-rc1\n"
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lean4",
          version: "4.27.0-rc1",
          requirements: [{
            requirement: "4.27.0-rc1",
            file: "lean-toolchain",
            groups: [],
            source: { type: "default" }
          }],
          package_manager: "lean"
        )
      end

      it "returns the latest version including RCs" do
        expect(checker.latest_version).to eq("4.28.0")
      end
    end
  end

  describe "#updated_requirements" do
    it "returns updated requirements with the latest version" do
      expect(checker.updated_requirements).to eq(
        [{
          requirement: "4.28.0",
          file: "lean-toolchain",
          groups: [],
          source: { type: "default" }
        }]
      )
    end
  end
end
