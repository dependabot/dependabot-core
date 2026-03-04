# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/file_updater"
require "dependabot/dependency"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Deno::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
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
  let(:files) do
    [
      Dependabot::DependencyFile.new(
        name: "deno.json",
        content: '{"imports": {"@std/path": "jsr:@std/path@^1.0.0", "chalk": "npm:chalk@^5.3.0"}}'
      )
    ]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "@std/path",
      version: "1.1.4",
      previous_version: "1.0.0",
      requirements: [{
        requirement: "^1.1.4",
        file: "deno.json",
        groups: ["imports"],
        source: { type: "jsr" }
      }],
      previous_requirements: [{
        requirement: "^1.0.0",
        file: "deno.json",
        groups: ["imports"],
        source: { type: "jsr" }
      }],
      package_manager: "deno"
    )
  end

  describe "#updated_dependency_files" do
    it "updates the specifier in deno.json" do
      updated_files = updater.updated_dependency_files
      expect(updated_files.length).to eq(1)

      updated_content = updated_files.first.content
      expect(updated_content).to include("jsr:@std/path@^1.1.4")
      expect(updated_content).to include("npm:chalk@^5.3.0")
    end
  end
end
