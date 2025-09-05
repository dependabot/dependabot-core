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

  let(:dependency_name) { "github.com/microsoft/vcpkg" }
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
      allow(latest_version_finder).to receive(:latest_version).and_return(mock_latest_version)
    end

    it "returns the latest version from the version finder" do
      expect(latest_version).to eq(mock_latest_version)
    end

    it "memoizes the result" do
      2.times { checker.latest_version }
      expect(latest_version_finder).to have_received(:latest_version).once
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
      allow(latest_version_finder).to receive(:latest_version).and_return(mock_latest_version)
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
      allow(latest_version_finder).to receive(:latest_version).and_return(mock_latest_version)
    end

    it "returns the same as latest_version for vcpkg baselines" do
      expect(latest_resolvable_version_with_no_unlock).to eq(mock_latest_version)
    end

    it "memoizes the result" do
      2.times { checker.latest_resolvable_version_with_no_unlock }
      expect(latest_version_finder).to have_received(:latest_version).once
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
        allow(latest_version_finder).to receive(:latest_version).and_return(nil)
      end

      it "returns the original requirements" do
        expect(updated_requirements).to eq(dependency.requirements)
      end
    end

    context "when there is a latest version" do
      let(:latest_version) { "2025.06.13" }
      let(:commit_sha) { "abc123def456789" }
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }
      let(:mock_latest_release_info) do
        instance_double(
          Dependabot::Package::PackageRelease,
          details: { "commit_sha" => commit_sha, "tag_sha" => "tag123" }
        )
      end

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder)
          .to receive(:latest_version)
          .and_return(latest_version)
        allow(latest_version_finder)
          .to receive_messages(
            latest_version: latest_version,
            latest_release_info: mock_latest_release_info
          )
      end

      it "updates the git ref to the commit SHA from the latest release" do
        expect(updated_requirements).to eq([{
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/microsoft/vcpkg.git",
            ref: commit_sha
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
    context "when git repository is not reachable" do
      let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

      before do
        allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
          .to receive(:new)
          .and_return(latest_version_finder)
        allow(latest_version_finder).to receive(:latest_version).and_return(nil)
      end

      it "returns nil for latest version" do
        expect(checker.latest_version).to be_nil
      end

      it "returns original requirements when no update is available" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end
  end

  describe "port dependencies" do
    let(:dependency_name) { "curl" }
    let(:dependency_version) { "8.10.0" }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        requirements: [{
          requirement: ">=#{dependency_version}",
          groups: [],
          source: nil,
          file: "vcpkg.json"
        }],
        package_manager: "vcpkg"
      )
    end

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "vcpkg.json",
          content: %(
            {
              "name": "test",
              "version": "1.0.0",
              "dependencies": [
                {
                  "name": "curl",
                  "version>=": "#{dependency_version}"
                }
              ]
            }
          ),
          directory: "/"
        )
      ]
    end

    describe "#updated_requirements" do
      subject(:updated_requirements) { checker.updated_requirements }

      context "when there is a latest version" do
        let(:latest_version) { "8.15.0#1" }
        let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

        before do
          allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
            .to receive(:new)
            .and_return(latest_version_finder)
          allow(latest_version_finder).to receive(:latest_version).and_return(latest_version)
        end

        it "updates the version constraint" do
          expect(updated_requirements).to eq([{
            requirement: ">=#{latest_version}",
            groups: [],
            source: nil,
            file: "vcpkg.json"
          }])
        end
      end

      context "when there is no latest version" do
        let(:latest_version_finder) { instance_double(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder) }

        before do
          allow(Dependabot::Vcpkg::UpdateChecker::LatestVersionFinder)
            .to receive(:new)
            .and_return(latest_version_finder)
          allow(latest_version_finder).to receive(:latest_version).and_return(nil)
        end

        it "returns the original requirements" do
          expect(updated_requirements).to eq(dependency.requirements)
        end
      end
    end

    describe "#port_dependency?" do
      subject(:port_dependency) { checker.send(:port_dependency?) }

      it "returns true for non-baseline dependencies" do
        expect(port_dependency).to be(true)
      end
    end
  end
end
