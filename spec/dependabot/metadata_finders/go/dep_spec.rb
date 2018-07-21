# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/metadata_finders/go/dep"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Go::Dep do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "2.1.0",
      requirements: requirements,
      package_manager: "dep"
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

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "with a github name" do
      it { is_expected.to eq("https://github.com/satori/go.uuid") }

      context "and no requirements" do
        it { is_expected.to eq("https://github.com/satori/go.uuid") }
      end

      context "that uses golang.org" do
        let(:dependency_name) { "golang.org/x/text" }
        it { is_expected.to eq("https://github.com/golang/text") }
      end
    end

    context "with a source" do
      let(:source) do
        {
          type: "default",
          source: "github.com/alias/go.uuid",
          branch: nil,
          ref: nil
        }
      end

      it { is_expected.to eq("https://github.com/alias/go.uuid") }
    end
  end
end
