# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/elm/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Elm::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "14.0.0",
      requirements: [{
        file: "elm-package.json",
        requirement: "14.0.0 <= v <= 14.0.0",
        groups: [],
        source: nil
      }],
      previous_version: "13.1.1",
      previous_requirements: [{
        file: "elm-package.json",
        requirement: "13.1.1 <= v <= 13.1.1",
        groups: [],
        source: nil
      }],
      package_manager: "elm"
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
  let(:dependency_name) { "rtfeldman/elm-css" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    it { is_expected.to eq("https://github.com/rtfeldman/elm-css") }
  end
end
