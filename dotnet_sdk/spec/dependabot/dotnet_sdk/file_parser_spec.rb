# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/dotnet_sdk/file_parser"
require "dependabot/dotnet_sdk/requirement"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::DotnetSdk::FileParser do
  let(:dependencies) { parser.parse }
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:files) do
    project_dependency_files(project_name, directory: directory)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/dotnet-sdk-example",
      directory: directory
    )
  end
  let(:parser) do
    described_class.new(dependency_files: files, source: source, repo_contents_path: repo_contents_path)
  end

  it_behaves_like "a dependency file parser"

  shared_examples_for "parse" do
    it "parses dependencies fine" do
      expect(dependencies.size).to eq(expectations.size)

      expectations.each do |expected|
        version = expected[:version]
        name = expected[:name]
        requirements = expected[:requirements]
        metadata = expected[:metadata]

        dependency = dependencies.find { |dep| dep.name == name }
        expect(dependency).to have_attributes(
          name: name,
          version: version,
          requirements: requirements,
          metadata: metadata
        )
      end
    end
  end

  context "with a global.json in repo root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }

    let(:expectations) do
      [
        {
          name: "dotnet-sdk",
          version: "8.0.300",
          requirements: [{
            file: "global.json",
            groups: [],
            requirement: "8.0.300",
            source: nil
          }],
          metadata: {
            allow_prerelease: false,
            roll_forward: "latestPatch"
          }
        }
      ].freeze
    end

    it_behaves_like "parse"
  end
end
