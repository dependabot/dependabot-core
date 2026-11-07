# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/elm/file_updater/elm_json_updater"

RSpec.describe Dependabot::Elm::FileUpdater::ElmJsonUpdater do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Elm::FileUpdater::ElmJsonUpdater) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:updater) do
    described_class.new(
      elm_json_file: elm_json_file,
      dependencies: [dependency]
    )
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:elm_json_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm_jsons", elm_json_file_fixture_name),
      name: "elm.json"
    )
  end
  sig { returns(String) }
  let(:elm_json_file_fixture_name) { "app.json" }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "elm/regex",
      version: "1.1.0",
      requirements: [{
        file: "elm.json",
        requirement: "1.1.0",
        groups: [],
        source: nil
      }],
      previous_version: "1.0.0",
      previous_requirements: [{
        file: "elm.json",
        requirement: "1.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "elm"
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#updated_content" do
    sig { returns(T.nilable(String)) }
    subject(:updated_content) { updater.updated_content }

    it "updates the right dependency" do
      expect(updated_content)
        .to include(%("elm/regex": "1.1.0"))
      expect(updated_content)
        .to include(%("elm/html": "1.0.0"))
    end
  end
end
