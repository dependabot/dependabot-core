# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elm/elm_package/version_resolver"
require "dependabot/file_parsers/elm/elm_package"

namespace = Dependabot::UpdateCheckers::Elm::ElmPackage
RSpec.describe namespace::VersionResolver do
  let(:max_version) { Dependabot::FileParsers::Elm::ElmPackage::MAX_VERSION }
  let(:elm_version) { Dependabot::Utils::Elm::Version }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      versions: versions
    )
  end
  let(:unlock_requirement) { true }
  let(:dependency_files) { [elm_package] }
  let(:versions) { [elm_version.new("13.1.1"), elm_version.new("14.0.0")] }
  let(:elm_package) do
    Dependabot::DependencyFile.new(
      name: "elm-package.json",
      content: fixture("elm", "elm_package", fixture_name)
    )
  end
  let(:fixture_name) { "version_resolver_one_simple_dep" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "elm-package"
    )
  end
  let(:dependency_name) { "rtfeldman/elm-css" }
  let(:dependency_version) { elm_version.new("13.1.1") }
  let(:dependency_requirements) do
    [{
      file: "elm-package.json",
      requirement: dependency_requirement,
      groups: ["default"],
      source: nil
    }]
  end
  let(:dependency_requirement) { "13.1.1 <= v <= 13.1.1" }

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version(unlock_requirement: unlock_requirement) }

    context "allowing :none unlocks" do
      let(:unlock_requirement) { false }

      it { is_expected.to eq(dependency_version) }
    end

    context "1) clean bump" do
      let(:dependency_version) { elm_version.new("13.1.1") }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version.new("14.0.0")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version.new("14.0.0")) }
      end
    end

    context "2) forced full unlock" do
      let(:fixture_name) { "elm_css_and_datetimepicker" }
      let(:dependency_name) { "NoRedInk/datetimepicker" }
      let(:dependency_requirement) { "3.0.1 <= v <= 3.0.1" }
      let(:dependency_version) { elm_version.new("3.0.1") }
      let(:versions) { [elm_version.new("3.0.1"), elm_version.new("3.0.2")] }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version.new("3.0.1")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version.new("3.0.2")) }
      end
    end

    context "3) downgrade bug" do
      let(:fixture_name) { "elm_css_and_datetimepicker" }
      let(:dependency_name) { "rtfeldman/elm-css" }
      let(:dependency_requirement) { "13.1.1 <= v <= 13.1.1" }
      let(:dependency_version) { elm_version.new("13.1.1") }
      let(:versions) { [elm_version.new("13.1.1"), elm_version.new("14.0.0")] }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version.new("13.1.1")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version.new("13.1.1")) }
      end
    end

    context "3) a <= v < b that doesn't require :own unlock" do
      let(:fixture_name) { "version_resolver_one_dep_lower_than" }
      let(:dependency_version) { elm_version.new("14.#{max_version}.#{max_version}") }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version.new("14.#{max_version}.#{max_version}")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version.new("14.#{max_version}.#{max_version}")) }
      end
    end

    context "4) empty elm-stuff bug means we don't bump" do
      let(:fixture_name) { "version_resolver_one_dep_lower_than" }
      let(:dependency_version) { elm_version.new("14.#{max_version}.#{max_version}") }
      let(:versions) { [elm_version.new("999.1.1")] }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it { is_expected.to eq(elm_version.new("14.#{max_version}.#{max_version}")) }
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it { is_expected.to eq(elm_version.new("14.#{max_version}.#{max_version}")) }
      end
    end

    context "5) dependencies too far apart" do
      let(:fixture_name) { "version_resolver_elm_package_error" }
      let(:dependency_version) { elm_version.new("13.1.1") }

      context ":own unlocks" do
        let(:unlock_requirement) { :own }
        it "raises a helpful error" do
          expect { subject }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("I cannot find a set of packages that works")
          end
        end
      end

      context ":all unlocks" do
        let(:unlock_requirement) { :all }
        it "raises a helpful error" do
          expect { subject }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("I cannot find a set of packages that works")
          end
        end
      end
    end
  end
end
