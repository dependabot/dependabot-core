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

  describe "security advisory conversion" do
    let(:conda_advisory) do
      Dependabot::SecurityAdvisory.new(
        dependency_name: "numpy",
        package_manager: "conda",
        vulnerable_versions: ["< 1.22.0"],
        safe_versions: [">= 1.22.0"]
      )
    end
    let(:security_advisories) { [conda_advisory] }

    describe "#python_compatible_security_advisories" do
      it "converts conda advisories to python-compatible format" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        expect(python_advisories).to be_an(Array)
        expect(python_advisories.size).to eq(1)
      end

      it "normalizes package_manager to pip" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        expect(python_advisories.first.package_manager).to eq("pip")
      end

      it "preserves dependency name" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        expect(python_advisories.first.dependency_name).to eq("numpy")
      end

      it "converts vulnerable versions to python requirement objects" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        vulnerable_versions = python_advisories.first.vulnerable_versions
        expect(vulnerable_versions).to be_an(Array)
        expect(vulnerable_versions.first).to be_a(Dependabot::Python::Requirement)
        expect(vulnerable_versions.first.to_s).to eq("< 1.22.0")
      end

      it "converts safe versions to python requirement objects" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        safe_versions = python_advisories.first.safe_versions
        expect(safe_versions).to be_an(Array)
        expect(safe_versions.first).to be_a(Dependabot::Python::Requirement)
        expect(safe_versions.first.to_s).to eq(">= 1.22.0")
      end
    end

    context "with multiple advisories" do
      let(:another_advisory) do
        Dependabot::SecurityAdvisory.new(
          dependency_name: "scipy",
          package_manager: "conda",
          vulnerable_versions: ["< 1.8.0"],
          safe_versions: [">= 1.8.0"]
        )
      end
      let(:security_advisories) { [conda_advisory, another_advisory] }

      it "converts all advisories" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        expect(python_advisories.size).to eq(2)
        expect(python_advisories.map(&:dependency_name)).to contain_exactly("numpy", "scipy")
        expect(python_advisories.map(&:package_manager)).to all(eq("pip"))
      end
    end

    context "with empty security advisories" do
      let(:security_advisories) { [] }

      it "returns empty array" do
        python_advisories = finder.send(:python_compatible_security_advisories)
        expect(python_advisories).to be_empty
      end
    end
  end
end
