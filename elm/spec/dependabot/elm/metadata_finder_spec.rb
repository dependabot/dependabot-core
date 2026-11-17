# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/elm/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Elm::MetadataFinder do
  extend T::Sig

  sig { returns(Dependabot::Elm::MetadataFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:dependency_name) { "rtfeldman/elm-css" }
  sig { returns(T::Array[Dependabot::Credential]) }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  sig { returns(Dependabot::Dependency) }
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
  # rubocop:enable RSpec/ScatteredLet

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    sig { returns(T.nilable(String)) }
    subject(:source_url) { finder.source_url }

    it { is_expected.to eq("https://github.com/rtfeldman/elm-css") }
  end
end
