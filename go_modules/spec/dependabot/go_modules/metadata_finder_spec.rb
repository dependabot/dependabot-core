# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/go_modules/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GoModules::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:source) { nil }
  let(:dependency_name) { "github.com/satori/go.uuid" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:requirements) do
    [{
      file: "go.mod",
      requirement: "v2.1.0",
      groups: [],
      source: source
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.1.0",
      requirements: requirements,
      package_manager: "go_modules"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "with no requirements (i.e., a subdependency)" do
      let(:requirements) { [] }

      it { is_expected.to eq("https://github.com/satori/go.uuid") }

      context "when dealing with a golang.org project" do
        let(:dependency_name) { "golang.org/x/text" }

        it { is_expected.to eq("https://github.com/golang/text") }
      end
    end

    context "with default requirements" do
      let(:source) do
        {
          type: "default",
          source: "github.com/alias/go.uuid"
        }
      end

      it { is_expected.to eq("https://github.com/satori/go.uuid") }
    end
  end
end
