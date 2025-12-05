# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/luarocks/update_checker"

RSpec.describe Dependabot::Luarocks::UpdateChecker do
  let(:dependency_files) { [rockspec_file] }
  let(:rockspec_file) do
    Dependabot::DependencyFile.new(
      name: "demo.rockspec",
      content: <<~ROCKSPEC
        dependencies = {
          "luafilesystem >= 1.7.0-1"
        }
      ROCKSPEC
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "luafilesystem",
      package_manager: "luarocks",
      requirements: [
        {
          requirement: ">= 1.7.0-1",
          file: "demo.rockspec",
          groups: [],
          source: nil
        }
      ],
      version: nil
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      security_advisories: [],
      raise_on_ignored: false,
      requirements_update_strategy: nil
    )
  end

  before do
    stub_request(:get, "https://luarocks.org/manifest.json")
      .to_return(
        status: 200,
        body: <<~JSON
          {
            "repository": {
              "luafilesystem": {
                "1.7.0-1": [{"arch": "rockspec"}],
                "1.9.0-1": [{"arch": "rockspec"}]
              }
            }
          }
        JSON
      )
  end

  it "finds the latest version" do
    expect(checker.latest_version.to_s).to eq("1.9.0-1")
  end

  it "updates the requirements to the latest version" do
    requirements = checker.updated_requirements
    expect(requirements.first[:requirement]).to eq(">= 1.9.0-1")
  end
end
