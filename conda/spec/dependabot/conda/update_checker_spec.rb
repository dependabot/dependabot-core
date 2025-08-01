# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Conda::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end

  let(:dependency_files) { [environment_file] }
  let(:environment_file) do
    Dependabot::DependencyFile.new(
      name: "environment.yml",
      content: fixture("environment_simple.yml")
    )
  end

  let(:github_credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  # Mock the LatestVersionFinder to avoid external calls in tests
  let(:latest_version_finder) { instance_double(Dependabot::Conda::UpdateChecker::LatestVersionFinder) }
  let(:mock_latest_version) { Dependabot::Conda::Version.new("1.26.4") }
  let(:mock_security_fix_version) { Dependabot::Conda::Version.new("1.22.1") }

  before do
    allow(Dependabot::Conda::UpdateChecker::LatestVersionFinder)
      .to receive(:new).and_return(latest_version_finder)
    allow(latest_version_finder).to receive(:latest_version).and_return(mock_latest_version)
    allow(latest_version_finder).to receive(:lowest_security_fix_version).and_return(mock_security_fix_version)
  end

  describe "#can_update?" do
    context "with a conda dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "numpy",
          version: "1.21.0",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.21.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      # Phase 3: Update checking now works with delegation to Python ecosystem
      it "can detect updates when newer version is available" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "with a pip dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.25.1",
          package_manager: "conda",
          requirements: [{
            requirement: "==2.25.1",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }]
        )
      end

      # Override the mock for this context
      before do
        allow(latest_version_finder).to receive(:latest_version).and_return(Dependabot::Conda::Version.new("2.28.2"))
      end

      # Phase 3: Update checking now works with delegation to Python ecosystem
      it "can detect updates when newer version is available" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end
  end

  describe "#latest_version" do
    context "with a conda dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "numpy",
          version: "1.21.0",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.21.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "delegates to latest_version_finder" do
        expect(checker.latest_version).to eq(mock_latest_version)
        expect(latest_version_finder).to have_received(:latest_version)
      end
    end

    context "with a pip dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.25.1",
          package_manager: "conda",
          requirements: [{
            requirement: "==2.25.1",
            file: "environment.yml",
            source: nil,
            groups: ["pip"]
          }]
        )
      end

      it "delegates to latest_version_finder" do
        expect(checker.latest_version).to eq(mock_latest_version)
        expect(latest_version_finder).to have_received(:latest_version)
      end
    end
  end

  describe "#latest_resolvable_version" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: "=1.21.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    it "delegates to latest_version for now" do
      expect(checker.latest_resolvable_version).to eq(mock_latest_version)
    end
  end

  describe "#updated_requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: "=1.21.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    it "returns updated requirements with the latest version" do
      expected_requirements = [{
        requirement: "=1.26.4",
        file: "environment.yml",
        source: nil,
        groups: ["dependencies"]
      }]
      expect(checker.updated_requirements).to eq(expected_requirements)
    end
  end

  describe "#up_to_date?" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: dependency_version,
        package_manager: "conda",
        requirements: [{
          requirement: "=#{dependency_version}",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    context "when current version is older than latest" do
      let(:dependency_version) { "1.21.0" }

      it "returns false" do
        expect(checker.up_to_date?).to be(false)
      end
    end

    context "when current version equals latest" do
      let(:dependency_version) { "1.26.4" }

      it "returns true" do
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when current version is newer than latest" do
      let(:dependency_version) { "1.30.0" }

      it "returns true" do
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when latest version is nil" do
      let(:dependency_version) { "1.21.0" }
      let(:mock_latest_version) { nil }

      it "returns true" do
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when dependency version is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "numpy",
          version: nil,
          package_manager: "conda",
          requirements: [{
            requirement: ">=1.20.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "returns false" do
        expect(checker.up_to_date?).to be(false)
      end
    end
  end

  describe "#lowest_security_fix_version" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: "=1.21.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    it "delegates to latest_version_finder" do
      expect(checker.lowest_security_fix_version).to eq(mock_security_fix_version)
      expect(latest_version_finder).to have_received(:lowest_security_fix_version)
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: "=1.21.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    context "when dependency is vulnerable" do
      before do
        allow(checker).to receive(:vulnerable?).and_return(true)
      end

      it "returns the lowest security fix version" do
        expect(checker.lowest_resolvable_security_fix_version).to eq(mock_security_fix_version)
      end
    end

    context "when dependency is not vulnerable" do
      before do
        allow(checker).to receive(:vulnerable?).and_return(false)
      end

      it "raises an error" do
        expect { checker.lowest_resolvable_security_fix_version }.to raise_error("Dependency not vulnerable!")
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: "=1.21.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    it "returns true for exact version constraints (can be updated to new exact constraints)" do
      expect(checker.requirements_unlocked_or_can_be?).to be(true)
    end

    context "with a range constraint" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "numpy",
          version: "1.21.0",
          package_manager: "conda",
          requirements: [{
            requirement: ">=1.20.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      it "returns true for range constraints" do
        expect(checker.requirements_unlocked_or_can_be?).to be(true)
      end
    end
  end

  describe "#vulnerable?" do
    subject { checker.vulnerable? }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: ">=1.0.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    let(:mock_security_advisories) { [] }
    let(:ignored_versions) { [] }

    context "when dependency is not vulnerable" do
      before do
        allow(security_advisories).to receive(:any?).and_return(false)
      end

      it "returns false" do
        expect(subject).to be(false)
      end
    end

    context "when dependency is vulnerable" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "numpy",
            package_manager: "conda",
            vulnerable_versions: ["< 1.24.0"]
          )
        ]
      end
      let(:mock_latest_version_finder) { instance_double(Dependabot::Conda::UpdateChecker::LatestVersionFinder) }

      before do
        allow(checker).to receive(:latest_version_finder).and_return(mock_latest_version_finder)
        allow(mock_latest_version_finder).to receive(:lowest_security_fix_version).and_return(Dependabot::Conda::Version.new("1.24.0"))
      end

      it "returns true and memoizes the security fix version" do
        # First call
        expect(checker.vulnerable?).to be(true)
        expect(checker.lowest_resolvable_security_fix_version).to eq(Dependabot::Conda::Version.new("1.24.0"))

        # Second call should use memoized value
        allow(mock_latest_version_finder).to receive(:lowest_security_fix_version).and_return(nil)
        expect(checker.vulnerable?).to be(true)
        expect(checker.lowest_resolvable_security_fix_version).to eq(Dependabot::Conda::Version.new("1.24.0"))
      end
    end
  end

  describe "#updated_requirements" do
    context "when target_version is nil" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "numpy",
          version: "1.21.0",
          package_manager: "conda",
          requirements: [{
            requirement: "=1.21.0",
            file: "environment.yml",
            source: nil,
            groups: ["dependencies"]
          }]
        )
      end

      before do
        allow(checker).to receive(:latest_version).and_return(nil)
        allow(checker).to receive(:latest_resolvable_version).and_return(nil)
        allow(checker).to receive(:preferred_resolvable_version).and_return(nil)
      end

      it "returns existing requirements when target_version is nil" do
        result = checker.updated_requirements
        expect(result).to eq(dependency.requirements)
      end
    end
  end

  describe "#update_requirement_string" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: original_requirement,
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    let(:target_version) { "1.26.4" }

    context "with exact match requirement" do
      let(:original_requirement) { "=1.21.0" }

      it "updates to new exact match" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with equality requirement" do
      let(:original_requirement) { "==1.21.0" }

      it "updates to new equality" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("==1.26.4")
      end
    end

    context "with greater than or equal requirement" do
      let(:original_requirement) { ">=1.21.0" }

      it "updates minimum version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq(">=1.26.4")
      end
    end

    context "with greater than requirement" do
      let(:original_requirement) { ">1.21.0" }

      it "updates minimum version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq(">1.26.4")
      end
    end

    context "with tilde and equals requirement" do
      let(:original_requirement) { "~=1.21.0" }

      it "updates to new tilde equals requirement" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("~=1.26.4")
      end
    end

    context "with less than or equal requirement" do
      let(:original_requirement) { "<=1.21.0" }

      it "keeps the original requirement unchanged" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("<=1.21.0")
      end
    end

    context "with less than requirement" do
      let(:original_requirement) { "<1.21.0" }

      it "keeps the original requirement unchanged" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("<1.21.0")
      end
    end

    context "with not equal requirement" do
      let(:original_requirement) { "!=1.21.0" }

      it "keeps the original requirement unchanged" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("!=1.21.0")
      end
    end

    context "with unknown requirement format" do
      let(:original_requirement) { "someunknownformat" }

      it "defaults to exact match with new version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with star pattern" do
      let(:original_requirement) { "1.21.*" }

      it "defaults to exact match with new version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with tilde requirement (conda style)" do
      let(:original_requirement) { "~1.21.0" }

      it "defaults to exact match with new version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with compatible requirement" do
      let(:original_requirement) { "^1.21.0" }

      it "defaults to exact match with new version" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with whitespace in exact requirement" do
      let(:original_requirement) { "= 1.21.0" }

      it "defaults to exact match with new version (whitespace not preserved)" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end

    context "with whitespace in equality requirement" do
      let(:original_requirement) { "== 1.21.0" }

      it "defaults to exact match with new version (whitespace not preserved)" do
        result = checker.send(:update_requirement_string, original_requirement, target_version)
        expect(result).to eq("=1.26.4")
      end
    end
  end

  describe "#python_package?" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "numpy",
        version: "1.21.0",
        package_manager: "conda",
        requirements: [{
          requirement: ">=1.0.0",
          file: "environment.yml",
          source: nil,
          groups: ["dependencies"]
        }]
      )
    end

    context "when dependency name is in Python package list" do
      let(:dependency_name) { "requests" }

      it "returns true" do
        result = checker.send(:python_package?, dependency_name)
        expect(result).to be(true)
      end
    end

    context "when dependency name is not in Python package list" do
      let(:dependency_name) { "cmake" }

      it "returns false" do
        result = checker.send(:python_package?, dependency_name)
        expect(result).to be(false)
      end
    end
  end

  private

  def fixture(name)
    File.read(File.join(__dir__, "../../fixtures", name))
  end
end
