# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/update_checker"
require "webmock/rspec"

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
    [{ file: "environment.yml", requirement: "=1.21.0", groups: ["dependencies"], source: nil }]
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
    context "when dependency is from pip section" do
      let(:dependency_name) { "requests" }
      let(:dependency_requirements) do
        [{ file: "environment.yml", requirement: ">=2.25.0", groups: ["pip"], source: nil }]
      end
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

    context "when dependency is from conda section" do
      let(:dependency_requirements) do
        [{ file: "environment.yml", requirement: "=1.21.0", groups: ["dependencies"], source: nil }]
      end
      let(:conda_api_response) do
        {
          "name" => "numpy",
          "versions" => ["1.20.0", "1.21.0", "1.22.0", "1.23.0"],
          "latest_version" => "1.23.0",
          "home" => "https://numpy.org",
          "dev_url" => "https://github.com/numpy/numpy"
        }.to_json
      end

      before do
        stub_request(:get, "https://api.anaconda.org/package/conda-forge/numpy")
          .to_return(status: 200, body: conda_api_response, headers: { "Content-Type" => "application/json" })
      end

      it "returns package details from Conda API" do
        details = finder.package_details
        expect(details).not_to be_nil
        expect(details.dependency.name).to eq("numpy")
        expect(details.releases.first.version.to_s).to eq("1.23.0")
        expect(details.releases.first.latest).to be true
      end

      it "returns all available versions from Conda API" do
        details = finder.package_details
        # package_details returns ALL versions - filtering happens in latest_version
        expect(details.releases.map { |r| r.version.to_s }).to eq(["1.23.0", "1.22.0", "1.21.0", "1.20.0"])
      end

      context "with ignored versions" do
        let(:ignored_versions) { ["1.23.0"] }

        it "returns all versions including ignored ones" do
          details = finder.package_details
          # package_details returns ALL versions - filtering happens in latest_version
          expect(details.releases.map { |r| r.version.to_s }).to include("1.23.0", "1.22.0", "1.21.0", "1.20.0")
          # Latest version is still 1.23.0 in the list
          expect(details.releases.first.version.to_s).to eq("1.23.0")
        end
      end

      context "when package does not exist in Conda API" do
        before do
          # Stub all channels that will be tried during fallback
          stub_request(:get, "https://api.anaconda.org/package/conda-forge/numpy")
            .to_return(status: 404)
          stub_request(:get, "https://api.anaconda.org/package/anaconda/numpy")
            .to_return(status: 404)
          stub_request(:get, "https://api.anaconda.org/package/main/numpy")
            .to_return(status: 404)
        end

        it "returns nil" do
          expect(finder.package_details).to be_nil
        end
      end
    end
  end

  describe "requirement conversion for pip packages" do
    let(:dependency_requirements) do
      [{ file: "environment.yml", requirement: requirement_string, groups: ["pip"], source: nil }]
    end

    context "with conda equality requirement" do
      let(:requirement_string) { "=1.21.0" }

      it "converts conda equality to pip equality" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq("==1.21.0")
        expect(python_dependency.package_manager).to eq("pip")
      end
    end

    context "with conda wildcard requirement" do
      let(:requirement_string) { "=1.21.*" }

      it "converts conda wildcard to pip range" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq(">=1.21.0,<1.22.0")
      end
    end

    context "with conda range requirement" do
      let(:requirement_string) { ">=1.21.0,<1.25.0" }

      it "preserves conda range requirements" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq(">=1.21.0,<1.25.0")
      end
    end

    context "with multiple requirements" do
      let(:dependency_requirements) do
        [
          { file: "environment.yml", requirement: "=1.21.0", groups: ["pip"], source: nil },
          { file: "requirements.txt", requirement: ">=1.20.0", groups: ["pip"], source: nil }
        ]
      end

      it "converts all requirements appropriately" do
        python_dependency = finder.send(:python_compatible_dependency)
        expect(python_dependency.requirements.first[:requirement]).to eq("==1.21.0")
        expect(python_dependency.requirements.last[:requirement]).to eq(">=1.20.0")
      end
    end
  end

  describe "channel resolution" do
    let(:dependency_name) { "pandas" }
    let(:dependency_version) { "1.3.5" }

    describe "#channels_to_search (private method)" do
      context "when channel is specified in source" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "=1.3.5", groups: ["dependencies"],
             source: { channel: "bioconda" } }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              channels:
                - conda-forge
                - defaults
              dependencies:
                - pandas=1.3.5
            YAML
          )
        end

        it "includes channel from source as first priority" do
          channels = finder.send(:channels_to_search)
          expect(channels.first).to eq("bioconda")
        end
      end

      context "when channel prefix is in requirement string" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "conda-forge::=1.3.5", groups: ["dependencies"],
             source: nil }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              channels:
                - defaults
                - bioconda
              dependencies:
                - conda-forge::pandas=1.3.5
            YAML
          )
        end

        it "includes channel from requirement prefix as first priority" do
          channels = finder.send(:channels_to_search)
          expect(channels.first).to eq("conda-forge")
        end

        it "includes environment.yml channels after requirement prefix" do
          channels = finder.send(:channels_to_search)
          expect(channels).to include("conda-forge", "defaults")
          expect(channels.index("conda-forge")).to be < channels.index("defaults")
        end
      end

      context "when channel is only in environment.yml" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "=1.3.5", groups: ["dependencies"], source: nil }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              channels:
                - conda-forge
                - defaults
              dependencies:
                - pandas=1.3.5
            YAML
          )
        end

        it "includes all channels from environment.yml in order" do
          channels = finder.send(:channels_to_search)
          expect(channels[0]).to eq("conda-forge")
          expect(channels[1]).to eq("defaults")
        end
      end

      context "when no channel is specified anywhere" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "=1.3.5", groups: ["dependencies"], source: nil }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              dependencies:
                - pandas=1.3.5
            YAML
          )
        end

        it "includes default fallback channels" do
          channels = finder.send(:channels_to_search)
          expect(channels).to include("anaconda", "conda-forge", "main")
        end
      end

      context "when 'defaults' channel is specified" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "=1.3.5", groups: ["dependencies"], source: nil }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              channels:
                - defaults
              dependencies:
                - pandas=1.3.5
            YAML
          )
        end

        it "includes 'defaults' channel from environment.yml" do
          channels = finder.send(:channels_to_search)
          expect(channels).to include("defaults")
        end
      end
    end

    describe "integration: channel resolution affects API calls" do
      let(:conda_api_response) do
        {
          "name" => "pandas",
          "versions" => ["1.3.5", "1.4.0", "1.5.0"],
          "latest_version" => "1.5.0"
        }.to_json
      end

      context "when channel prefix is in requirement (conda-forge::)" do
        let(:dependency_requirements) do
          [{ file: "environment.yml", requirement: "conda-forge::=1.3.5", groups: ["dependencies"],
             source: nil }]
        end
        let(:environment_file) do
          Dependabot::DependencyFile.new(
            name: "environment.yml",
            content: <<~YAML
              channels:
                - defaults
                - bioconda
              dependencies:
                - conda-forge::pandas=1.3.5
            YAML
          )
        end

        before do
          stub_request(:get, "https://api.anaconda.org/package/conda-forge/pandas")
            .to_return(status: 200, body: conda_api_response, headers: { "Content-Type" => "application/json" })
        end

        it "queries conda-forge channel, not defaults" do
          finder.package_details

          expect(WebMock).to have_requested(:get, "https://api.anaconda.org/package/conda-forge/pandas")
          expect(WebMock).not_to have_requested(:get, "https://api.anaconda.org/package/defaults/pandas")
        end
      end
    end
  end

  describe "security advisory conversion for pip packages" do
    let(:dependency_requirements) do
      [{ file: "environment.yml", requirement: ">=2.0", groups: ["pip"], source: nil }]
    end
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
