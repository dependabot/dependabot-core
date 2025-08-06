# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker"

RSpec.describe Dependabot::Conda::UpdateChecker::LatestVersionFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      cooldown_options: cooldown_options
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "conda"
    )
  end
  let(:dependency_name) { "numpy" }
  let(:dependency_version) { "1.21.0" }
  let(:dependency_requirements) do
    [{ file: "environment.yml", requirement: "=1.21.0", groups: [], source: nil }]
  end
  let(:dependency_files) { [environment_file] }
  let(:environment_file) do
    Dependabot::DependencyFile.new(
      name: "environment.yml",
      content: fixture("environment_basic.yml")
    )
  end
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:cooldown_options) { nil }

  describe "#cooldown_enabled?" do
    it "returns true" do
      expect(finder.cooldown_enabled?).to be true
    end
  end

  describe "#package_details" do
    let(:python_finder) { instance_double(Dependabot::Python::UpdateChecker::LatestVersionFinder) }
    let(:package_details) { instance_double(Dependabot::Package::PackageDetails) }

    before do
      allow(Dependabot::Python::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(python_finder)
      allow(python_finder).to receive(:package_details).and_return(package_details)
    end

    it "delegates to python latest version finder" do
      expect(finder.package_details).to eq(package_details)
      expect(python_finder).to have_received(:package_details)
    end

    it "creates python-compatible dependency" do
      finder.package_details

      expect(Dependabot::Python::UpdateChecker::LatestVersionFinder)
        .to have_received(:new).with(
          dependency: an_instance_of(Dependabot::Dependency),
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          security_advisories: security_advisories,
          cooldown_options: cooldown_options
        )
    end
  end

  describe "requirement conversion" do
    context "with conda equality requirement" do
      let(:dependency_requirements) do
        [{ file: "environment.yml", requirement: "=1.21.0", groups: [], source: nil }]
      end

      it "converts conda equality to pip equality" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq("==1.21.0")
        expect(python_dependency.package_manager).to eq("pip")
      end
    end

    context "with conda wildcard requirement" do
      let(:dependency_requirements) do
        [{ file: "environment.yml", requirement: "=1.21.*", groups: [], source: nil }]
      end

      it "converts conda wildcard to pip range" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq(">=1.21.0,<1.22.0")
      end
    end

    context "with conda range requirement" do
      let(:dependency_requirements) do
        [{ file: "environment.yml", requirement: ">=1.21.0,<1.25.0", groups: [], source: nil }]
      end

      it "preserves conda range requirements" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq(">=1.21.0,<1.25.0")
      end
    end

    context "with multiple requirements" do
      let(:dependency_requirements) do
        [
          { file: "environment.yml", requirement: "=1.21.0", groups: [], source: nil },
          { file: "requirements.txt", requirement: ">=1.20.0", groups: [], source: nil }
        ]
      end

      it "converts all requirements appropriately" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq("==1.21.0")
        expect(python_dependency.requirements.last[:requirement]).to eq(">=1.20.0")
      end
    end
  end
end
