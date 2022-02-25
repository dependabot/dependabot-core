# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/go_modules/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::GoModules::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.1.0",
      requirements: requirements,
      package_manager: "go_modules"
    )
  end
  let(:requirements) do
    [{
      file: "Gopkg.toml",
      requirement: "v2.1.0",
      groups: [],
      source: source
    }]
  end
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
  let(:dependency_name) { "github.com/satori/go.uuid" }
  let(:source) { nil }

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "with no requirements (i.e., a subdependency)" do
      let(:requirements) { [] }

      it { is_expected.to eq("https://github.com/satori/go.uuid") }

      context "for a golang.org project" do
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

      it { is_expected.to eq("https://github.com/alias/go.uuid") }
    end

    context "with git requirements" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/alias/go.uuid",
          branch: "master",
          ref: nil
        }
      end

      it { is_expected.to eq("https://github.com/alias/go.uuid") }
    end
  end
end
