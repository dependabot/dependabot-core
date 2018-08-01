# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/elm/elm_package/elm_package_updater"

RSpec.describe Dependabot::FileUpdaters::Elm::ElmPackage::ElmPackageUpdater do
  let(:updater) do
    described_class.new(
      elm_package_file: elm_package_file,
      dependencies: [dependency]
    )
  end

  let(:elm_package_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm", "elm_package", elm_package_file_fixture_name),
      name: "elm-package.json"
    )
  end
  let(:elm_package_file_fixture_name) { "elm_css_and_datetimepicker" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rtfeldman/elm-css",
      version: "14.0.0",
      requirements:
        [{ file: "elm-package.json", requirement: "14.0.0 <= v <= 14.0.0", groups: [], source: nil }],
      previous_version: "13.1.1",
      previous_requirements:
        [{ file: "elm-package.json", requirement: "13.1.1 <= v <= 13.1.1", groups: [], source: nil }],
      package_manager: "elm-package"
    )
  end

  describe "#updated_elm_package_file_content" do
    subject(:updated_elm_package_file_content) { updater.updated_elm_package_file_content }

    it "updates the right dependency" do
      expect(updated_elm_package_file_content).
        to include(%("rtfeldman/elm-css": "14.0.0 <= v <= 14.0.0",))
      expect(updated_elm_package_file_content).
        to include(%("NoRedInk/datetimepicker": "3.0.1 <= v <= 3.0.1"))
    end

    context "with similarly named packages" do
      let(:elm_package_file_fixture_name) { "similar_names" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "some/awesome-package",
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
          package_manager: "elm-package"
        )
      end

      it "updates the right dependency" do
        expect(updated_elm_package_file_content).
          to include(%("some/awesome-package": "14.0.0 <= v <= 14.0.0",))
        expect(updated_elm_package_file_content).
          to include(%("ome/awesome-package": "3.0.1 <= v <= 3.0.1",))
        expect(updated_elm_package_file_content).
          to include(%("some/awesome-pack": "2.0.1 <= v <= 2.0.1"))
      end
    end
  end
end
