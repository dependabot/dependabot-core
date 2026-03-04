# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/update_checker"
require "dependabot/dependency"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Deno::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      security_advisories: [],
      ignored_versions: []
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
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "deno.json",
        content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0"}}'
      )
    ]
  end

  context "with a jsr dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@std/path",
        version: "1.0.0",
        requirements: [{
          requirement: "^1.0.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "jsr" }
        }],
        package_manager: "deno"
      )
    end

    before do
      stub_request(:get, "https://jsr.io/@std/path/meta.json")
        .to_return(
          status: 200,
          body: {
            scope: "std",
            name: "path",
            latest: "1.1.4",
            versions: {
              "1.1.4" => { "createdAt" => "2025-12-01T00:00:00Z" },
              "1.0.0" => { "createdAt" => "2024-01-01T00:00:00Z" }
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "finds the latest version" do
      expect(checker.latest_version).to eq(Dependabot::Deno::Version.new("1.1.4"))
    end

    it "finds the latest resolvable version" do
      expect(checker.latest_resolvable_version).to eq(Dependabot::Deno::Version.new("1.1.4"))
    end

    it "updates requirements" do
      updated = checker.updated_requirements
      expect(updated.first[:requirement]).to eq("^1.1.4")
    end
  end

  context "with an npm dependency" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "chalk",
        version: "5.3.0",
        requirements: [{
          requirement: "^5.3.0",
          file: "deno.json",
          groups: ["imports"],
          source: { type: "npm" }
        }],
        package_manager: "deno"
      )
    end

    before do
      stub_request(:get, "https://registry.npmjs.org/chalk")
        .to_return(
          status: 200,
          body: {
            "dist-tags" => { "latest" => "5.4.0" },
            "versions" => {
              "5.3.0" => {},
              "5.4.0" => {}
            },
            "time" => {
              "5.3.0" => "2024-01-01T00:00:00Z",
              "5.4.0" => "2025-06-01T00:00:00Z"
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "finds the latest version" do
      expect(checker.latest_version).to eq(Dependabot::Deno::Version.new("5.4.0"))
    end
  end
end
