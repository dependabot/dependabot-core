# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nuget/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Nuget::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:source) { nil }
  let(:dependency_version) { "2.1.0" }
  let(:dependency_name) { "Microsoft.Extensions.DependencyModel" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "nuget"
    )
  end

  let(:requirements) do
    [{
      file: "my.csproj",
      requirement: dependency_version,
      groups: ["dependencies"],
      source: source
    }]
  end

  it_behaves_like "a dependency metadata finder"

  describe "#dependency_source_url" do
    subject(:look_up_source) { finder.send(:dependency_source_url) }

    context "with a source object with symbol keys" do
      let(:source) do
        {
          source_url: "https://nuget.example.com/some.package",
          type: "nuget_repo"
        }
      end

      it { is_expected.to eq("https://nuget.example.com/some.package") }
    end

    context "with a source object with string keys" do
      let(:source) do
        {
          "source_url" => "https://nuget.example.com/some.package",
          "type" => "nuget_repo"
        }
      end

      it { is_expected.to eq("https://nuget.example.com/some.package") }
    end

    context "with a nil source object" do
      let(:source) { nil }

      it { is_expected.to be_nil }
    end

    context "with multiple requirements" do
      let(:requirements) do
        [{
          file: "project.csproj",
          requirement: dependency_version,
          groups: ["dependencies"],
          source: nil
        }, {
          file: "my.csproj",
          requirement: dependency_version,
          groups: ["dependencies"],
          source: source
        }]
      end

      let(:source) do
        {
          source_url: "https://nuget.example.com/some.package",
          type: "nuget_repo"
        }
      end

      it { is_expected.to eq("https://nuget.example.com/some.package") }
    end
  end
end
