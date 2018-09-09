# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/elm/elm_package/elm_json_updater"

RSpec.describe Dependabot::FileUpdaters::Elm::ElmPackage::ElmJsonUpdater do
  let(:updater) do
    described_class.new(
      elm_json_file: elm_json_file,
      dependencies: [dependency]
    )
  end

  let(:elm_json_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm", "elm_jsons", elm_json_file_fixture_name),
      name: "elm.json"
    )
  end
  let(:elm_json_file_fixture_name) { "app.json" }

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
      package_manager: "elm-package"
    )
  end

  describe "#updated_content" do
    subject(:updated_content) { updater.updated_content }

    it "updates the right dependency" do
      expect(updated_content).
        to include(%("elm/regex": "1.1.0"))
      expect(updated_content).
        to include(%("elm/html": "1.0.0"))
    end
  end
end
