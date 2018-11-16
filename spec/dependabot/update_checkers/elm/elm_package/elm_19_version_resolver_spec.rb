# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_parsers/elm/elm_package"
require "dependabot/update_checkers/elm/elm_package/elm_19_version_resolver"

namespace = Dependabot::UpdateCheckers::Elm::ElmPackage
RSpec.describe namespace::Elm19VersionResolver do
  def elm_version(version_string)
    Dependabot::Utils::Elm::Version.new(version_string)
  end

  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files
    )
  end
  let(:unlock_requirement) { :own }
  let(:dependency_files) { [elm_json] }
  let(:elm_json) do
    Dependabot::DependencyFile.new(
      name: "elm.json",
      content: fixture("elm", "elm_jsons", fixture_name)
    )
  end
  let(:fixture_name) { "app.json" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "elm-package"
    )
  end
  let(:dependency_name) { "elm/parser" }
  let(:dependency_version) { "1.0.0" }
  let(:dependency_requirements) { [] }
  let(:dependency_requirement) { "1.0.0" }

  describe "#latest_resolvable_version" do
    subject do
      resolver.latest_resolvable_version(unlock_requirement: unlock_requirement)
    end

    context "for an app" do
      context "allowing no unlocks" do
        let(:unlock_requirement) { :none }
        it { is_expected.to eq(elm_version(dependency_version)) }
      end

      context "with an update that only changes a single version" do
        context ":own unlocks" do
          let(:unlock_requirement) { :own }
          it { is_expected.to eq(elm_version("1.1.0")) }
        end

        context ":all unlocks" do
          let(:unlock_requirement) { :all }
          it { is_expected.to eq(elm_version("1.1.0")) }
        end
      end

      context "with an unsupported dependency" do
        let(:fixture_name) { "unsupported_dep.json" }
        let(:dependency_name) { "NoRedInk/datetimepicker" }
        let(:dependency_version) { "3.0.0" }
        let(:dependency_requirement) { "3.0.0" }

        it "raises a DependencyFileNotResolvable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).to_not include("dependabot_20")
              expect(error.message).to include("do not work with Elm 0.19.0")
            end
        end
      end

      context "with an invalid file layout" do
        let(:fixture_name) { "invalid_layout.json" }
        let(:dependency_name) { "elm/regex" }
        let(:dependency_version) { "1.0.0" }
        let(:dependency_requirement) { "1.0.0" }

        it "raises a DependencyFileNotResolvable error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              # Test that the temporary path isn't included in the error message
              expect(error.message).to_not include("dependabot_20")
              expect(error.message).to include("object at project.dependencies")
            end
        end
      end

      context "with multiple updates required" do
        let(:fixture_name) { "full_unlock_required.json" }
        let(:dependency_name) { "elm/http" }
        let(:dependency_version) { "1.0.0" }
        let(:dependency_requirement) { "1.0.0" }

        it { is_expected.to eq(elm_version(dependency_version)) }

        context ":all unlocks" do
          let(:unlock_requirement) { :all }

          # TODO: Full unlocks don't work yet! We need to work on how we use elm
          it { is_expected.to eq(elm_version(dependency_version)) }
        end
      end

      context "with indirect dependency updates required" do
        let(:fixture_name) { "indirect_updates_required.json" }
        let(:dependency_name) { "elm/http" }
        let(:dependency_version) { "1.0.0" }
        let(:dependency_requirement) { "1.0.0" }

        it { is_expected.to be >= elm_version("2.0.0") }
      end
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject(:updated_deps) { resolver.updated_dependencies_after_full_unlock }

    context "with multiple updates required" do
      let(:fixture_name) { "full_unlock_required.json" }
      let(:dependency_name) { "elm/http" }
      let(:dependency_version) { "1.0.0" }
      let(:dependency_requirement) { "1.0.0" }

      # TODO: Full unlocks don't work yet! We need to work on how we use elm
      it "updates the right dependencies" do
        expect(updated_deps).to eq([])
      end
    end
  end
end
