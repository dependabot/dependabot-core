# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"

require "dependabot/vcpkg/file_parser"
require "dependabot/vcpkg/update_checker"
require "dependabot/vcpkg/version"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Vcpkg::UpdateChecker do
  subject(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories,
      options: options
    )
  end

  let(:dependency_name) { "baseline" }
  let(:dependency_version) { "2025.04.09" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: [{
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/vcpkg.git",
          ref: dependency_version
        },
        file: "vcpkg.json"
      }],
      package_manager: "vcpkg"
    )
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "vcpkg.json",
        content: '{"name": "test", "version": "1.0.0", "builtin-baseline": "' + dependency_version + '"}',
        directory: "/"
      )
    ]
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:options) { {} }

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }
    let(:mock_latest_version) { "2025.06.13" }

    before do
      allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
        .to receive(:new)
        .and_return(latest_version_finder)
      allow(latest_version_finder).to receive(:latest_tag).and_return(mock_latest_version)
    end

    it "returns the latest version from the version finder" do
      expect(latest_version).to eq(mock_latest_version)
    end

    it "memoizes the result" do
      2.times { checker.latest_version }
      expect(latest_version_finder).to have_received(:latest_tag).once
    end

    context "when no latest version is available" do
      let(:mock_latest_version) { nil }

      it "returns nil" do
        expect(latest_version).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }
    let(:mock_latest_version) { "2025.06.13" }

    before do
      allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
        .to receive(:new)
        .and_return(latest_version_finder)
      allow(latest_version_finder).to receive(:latest_tag).and_return(mock_latest_version)
    end

    it "returns the same as latest_version for vcpkg baselines" do
      expect(latest_resolvable_version).to eq(mock_latest_version)
    end

    context "when no latest version is available" do
      let(:mock_latest_version) { nil }

      it "returns nil" do
        expect(latest_resolvable_version).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:latest_resolvable_version_with_no_unlock) { checker.latest_resolvable_version_with_no_unlock }

    let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }
    let(:mock_latest_version) { "2025.06.13" }

    before do
      allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
        .to receive(:new)
        .and_return(latest_version_finder)
      allow(latest_version_finder).to receive(:latest_tag).and_return(mock_latest_version)
    end

    it "returns the same as latest_version for vcpkg baselines" do
      expect(latest_resolvable_version_with_no_unlock).to eq(mock_latest_version)
    end

    it "memoizes the result" do
      2.times { checker.latest_resolvable_version_with_no_unlock }
      expect(latest_version_finder).to have_received(:latest_tag).once
    end

    context "when no version is available" do
      let(:mock_latest_version) { nil }

      it "returns nil" do
        expect(latest_resolvable_version_with_no_unlock).to be_nil
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    context "when there is no latest version" do
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder).to receive(:latest_tag).and_return(nil)
      end

      it "returns the original requirements" do
        expect(updated_requirements).to eq(dependency.requirements)
      end
    end

    context "when there is a latest version" do
      let(:latest_version) { "2025.06.13" }
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder).to receive(:latest_tag).and_return(latest_version)
      end

      it "updates the git ref to the new version" do
        expect(updated_requirements).to eq([{
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/microsoft/vcpkg.git",
            ref: latest_version
          },
          file: "vcpkg.json"
        }])
      end

      context "when requirement has no source" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: dependency_version,
            requirements: [{
              requirement: nil,
              groups: [],
              source: nil,
              file: "vcpkg.json"
            }],
            package_manager: "vcpkg"
          )
        end

        it "returns the original requirement unchanged" do
          expect(updated_requirements).to eq([{
            requirement: nil,
            groups: [],
            source: nil,
            file: "vcpkg.json"
          }])
        end
      end

      context "with multiple requirements" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: dependency_version,
            requirements: [
              {
                requirement: nil,
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/microsoft/vcpkg.git",
                  ref: dependency_version
                },
                file: "vcpkg.json"
              },
              {
                requirement: nil,
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/microsoft/vcpkg.git",
                  ref: dependency_version
                },
                file: "vcpkg-configuration.json"
              }
            ],
            package_manager: "vcpkg"
          )
        end

        it "updates all requirements with git sources" do
          expect(updated_requirements).to eq([
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: latest_version
              },
              file: "vcpkg.json"
            },
            {
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/microsoft/vcpkg.git",
                ref: latest_version
              },
              file: "vcpkg-configuration.json"
            }
          ])
        end
      end
    end
  end

  describe "#latest_version_resolvable_with_full_unlock?" do
    subject(:latest_version_resolvable_with_full_unlock) do
      checker.send(:latest_version_resolvable_with_full_unlock?)
    end

    it "always returns false for vcpkg baselines" do
      expect(latest_version_resolvable_with_full_unlock).to be(false)
    end
  end

  describe "#updated_dependencies_after_full_unlock" do
    subject(:updated_dependencies_after_full_unlock) { checker.send(:updated_dependencies_after_full_unlock) }

    it "raises NotImplementedError" do
      expect { updated_dependencies_after_full_unlock }.to raise_error(NotImplementedError)
    end
  end

  describe "#latest_version_finder" do
    subject(:latest_version_finder) { checker.send(:latest_version_finder) }

    it "creates a LatestVersionFinder with correct parameters" do
      expect(latest_version_finder).to be_a(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
    end

    it "memoizes the result" do
      finder1 = checker.send(:latest_version_finder)
      finder2 = checker.send(:latest_version_finder)
      expect(finder1).to be(finder2)
    end
  end

  describe "inheritance" do
    it "inherits from UpdateCheckers::Base" do
      expect(described_class.superclass).to eq(Dependabot::UpdateCheckers::Base)
    end
  end

  describe "integration" do
    context "when checking for updates with mocked git tags" do
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }
      let(:mock_latest_tag) { "2025.06.13" }

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder).to receive(:latest_tag).and_return(mock_latest_tag)
      end

      it "can find the latest version" do
        expect(checker.latest_version).to eq("2025.06.13")
      end

      it "updates requirements correctly" do
        updated_reqs = checker.updated_requirements
        expect(updated_reqs.first[:source][:ref]).to eq("2025.06.13")
      end
    end

    context "when git repository is not reachable" do
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder).to receive(:latest_tag).and_return(nil)
      end

      it "returns nil for latest version" do
        expect(checker.latest_version).to be_nil
      end

      it "returns original requirements when no update is available" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end
  end
end
