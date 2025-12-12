# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/luarocks/file_updater"

RSpec.describe Dependabot::Luarocks::FileUpdater do
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "luafilesystem",
      package_manager: "luarocks",
      requirements: [
        {
          requirement: ">= 1.9.0-1",
          file: "demo.rockspec",
          groups: [],
          source: nil
        }
      ],
      previous_requirements: [
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
  let(:dependency_files) { [rockspec_file] }
  let(:rockspec_file) do
    Dependabot::DependencyFile.new(
      name: "demo.rockspec",
      content: <<~ROCKSPEC
        dependencies = {
          "luafilesystem >= 1.7.0-1",
          "lua >= 5.1"
        }
      ROCKSPEC
    )
  end
  let(:updater) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      credentials: []
    )
  end

  it "updates the dependency requirement in the rockspec" do
    updated_files = updater.updated_dependency_files
    expect(updated_files.length).to eq(1)
    expect(updated_files.first.content).to include("luafilesystem >= 1.9.0-1")
  end
end
