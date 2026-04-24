# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::PreCommit::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/pre-commit/pre-commit-hooks",
      ref: "v4.4.0",
      branch: nil
    }
  end
  let(:dependency_name) { "https://github.com/pre-commit/pre-commit-hooks" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "v4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: dependency_source
      }],
      package_manager: "pre_commit"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when dealing with a git source" do
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/pre-commit/pre-commit-hooks",
          ref: "v4.4.0",
          branch: nil
        }
      end

      it { is_expected.to eq("https://github.com/pre-commit/pre-commit-hooks") }
    end

    context "when dealing with a subdependency (no requirements)" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "v4.4.0",
          requirements: [],
          package_manager: "pre_commit"
        )
      end

      it { is_expected.to eq("https://github.com/pre-commit/pre-commit-hooks") }
    end

    context "when dealing with a gitlab source" do
      let(:dependency_name) { "https://gitlab.com/pycqa/flake8" }
      let(:dependency_source) do
        {
          type: "git",
          url: "https://gitlab.com/pycqa/flake8",
          ref: "v5.0.0",
          branch: nil
        }
      end

      it { is_expected.to eq("https://gitlab.com/pycqa/flake8") }
    end
  end
end
