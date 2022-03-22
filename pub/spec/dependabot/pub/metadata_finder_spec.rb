# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pub/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Pub::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  before do
    stub_request(:get, "https://pub.dev/api/packages/#{dependency.name}").to_return(
      status: 200,
      body: fixture("pub_dev_responses/simple/#{dependency.name}.json"),
      headers: {}
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "retry",
      version: "1.3.0",
      requirements: [{
        file: "pubspec.yaml",
        requirement: "~3.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "pub"
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#source_url" do
    it "finds the repository" do
      expect(finder.source_url).to eq "https://github.com/google/dart-neats"
    end
  end

  describe "#source_url" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "protobuf",
        version: "2.0.1",
        requirements: [{
          file: "pubspec.yaml",
          requirement: "~3.0.0",
          groups: [],
          source: nil
        }],
        package_manager: "pub"
      )
    end
    it "falls back to the homepage field" do
      expect(finder.source_url).to eq "https://github.com/dart-lang/protobuf"
    end
  end
end
