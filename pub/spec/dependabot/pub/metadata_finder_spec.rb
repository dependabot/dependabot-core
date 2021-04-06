# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pub/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Pub::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "path",
      version: "1.8.0",
      previous_version: "1.7.0",
      requirements: [{
        requirement: "git@github.com:dart-lang/path.git",
        groups: ["dependencies"],
        file: "pubspec.yaml",
        source: {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          path: ".",
          branch: nil,
          ref: "1.8.0",
          resolved_ref: "407ab76187fade41c31e39c745b39661b710106c"
        }
      }],
      previous_requirements: [{
        requirement: "git@github.com:dart-lang/path.git",
        groups: ["dependencies"],
        file: "pubspec.yaml",
        source: {
          type: "git",
          url: "git@github.com:dart-lang/path.git",
          path: ".",
          branch: nil,
          ref: "1.7.0",
          resolved_ref: "10c778c799b2fc06036cbd0aa0e399ad4eb1ff5b"
        }
      }],
      package_manager: "pub"
    )
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
  let(:dependency_name) { "path" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    it { is_expected.to eq("https://github.com/dart-lang/path") }

    context "with a hosted dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "path",
          version: "1.8.0",
          previous_version: "1.7.0",
          requirements: [{
            requirement: "^1.8.0",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dartlang.org"
            }
          }],
          previous_requirements: [{
            requirement: "^1.7.0",
            groups: ["dependencies"],
            file: "pubspec.yaml",
            source: {
              type: "hosted",
              url: "https://pub.dartlang.org"
            }
          }],
          package_manager: "pub"
        )
      end

      let(:hosted_url) do
        "https://pub.dartlang.org/api/packages/path"
      end
      let(:hosted_response) do
        fixture("hosted_responses", "path_versions.json")
      end
      before do
        stub_request(:get, hosted_url).
          to_return(status: 200, body: hosted_response)
      end

      it do
        is_expected.to eq("https://github.com/dart-lang/path")
      end
    end
  end
end
