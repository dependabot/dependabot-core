# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cocoapods/update_checker"
require "dependabot/cocoapods/version"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::CocoaPods::UpdateChecker do
  it_behaves_like "an update checker"

  COCOAPODS_CDN_HOST = "https://cdn.cocoapods.org"

  before do
    master_url = "https://api.github.com/repos/CocoaPods/Specs/commits/master"
    stub_request(:get, master_url).to_return(status: 304)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_files) { [podfile, podfile_lock] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Alamofire",
      version: "3.0.0",
      requirements: requirements,
      package_manager: "cocoapods"
    )
  end

  let(:requirements) do
    [{
      requirement: "~> 3.0.0",
      file: "Podfile",
      groups: [],
      source: source
    }]
  end

  let(:source) { nil }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:podfile) do
    Dependabot::DependencyFile.new(
      name: "Podfile",
      content: podfile_content
    )
  end

  let(:podfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Podfile.lock",
      content: lockfile_content
    )
  end

  let(:podfile_content) do
    fixture("cocoapods", "podfiles", "version_specified")
  end

  let(:lockfile_content) do
    fixture("cocoapods", "lockfiles", "version_specified")
  end

  let(:cocoapods_all_pods) do
    fixture("cocoapods", "all_pods", "all_pods.txt")
  end

  let(:cocoapods_deprecated_specs) do
    fixture("cocoapods", "podspecs", "deprecated_podspecs.txt")
  end

  let(:cocoapods_version_yaml) do
    fixture("cocoapods", "CocoaPods-version.yml")
  end

  let(:fixtures_path) do
    File.join("spec", "fixtures", "cocoapods")
  end

  let(:all_versions_files) do
    File.join(fixtures_path, "all_pods", "all_pods_versions_*.txt")
  end

  let(:podspec_files) do
    File.join(fixtures_path, "podspecs", "*.podspec.json")
  end

  def stub_all_pods_versions_requests
    Dir[all_versions_files].each do |file|
      versions_url = "#{COCOAPODS_CDN_HOST}/#{File.basename(file)}"
      stub_request(:get, versions_url).
        to_return(status: 200, body: File.read(file))
    end
  end

  def stub_all_spec_requests
    spec_paths = {
      "Nimble-0.0.1": "Specs/d/c/d/Nimble/0.0.1/Nimble.podspec.json",
      "Nimble-3.0.0": "Specs/d/c/d/Nimble/3.0.0/Nimble.podspec.json",
      "Alamofire-3.0.1": "Specs/d/a/2/Alamofire/3.0.1/Alamofire.podspec.json",
      "Alamofire-3.5.1": "Specs/d/a/2/Alamofire/3.5.1/Alamofire.podspec.json",
      "Alamofire-4.5.0": "Specs/d/a/2/Alamofire/4.5.0/Alamofire.podspec.json",
      "Alamofire-4.5.1": "Specs/d/a/2/Alamofire/4.5.1/Alamofire.podspec.json",
      "Alamofire-4.6.0": "Specs/d/a/2/Alamofire/4.6.0/Alamofire.podspec.json",
      "AlamofireImage-2.5.0":
          "Specs/8/0/a/AlamofireImage/2.5.0/AlamofireImage.podspec.json",
      "AlamofireImage-4.1.0":
          "Specs/8/0/a/AlamofireImage/4.1.0/AlamofireImage.podspec.json"
    }

    Dir[podspec_files].each do |file|
      spec = File.basename(file, ".podspec.json")
      spec_path = spec_paths[spec.to_sym]
      versions_url = "#{COCOAPODS_CDN_HOST}/#{spec_path}"

      stub_request(:get, versions_url).
        to_return(status: 200, body: File.read(file))
    end
  end

  before do
    all_pods_url = "#{COCOAPODS_CDN_HOST}/all_pods.txt"
    stub_request(:get, all_pods_url).
      to_return(status: 200, body: cocoapods_all_pods)

    deprecated_specs_url = "#{COCOAPODS_CDN_HOST}/deprecated_podspecs.txt"
    stub_request(:get, deprecated_specs_url).
      to_return(status: 200, body: cocoapods_deprecated_specs)

    cocoapods_version_url = "#{COCOAPODS_CDN_HOST}/CocoaPods-version.yml"
    stub_request(:get, cocoapods_version_url).
      to_return(status: 200, body: cocoapods_version_yaml)

    stub_all_pods_versions_requests
    stub_all_spec_requests
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "delegates to latest_resolvable_version" do
      expect(checker).to receive(:latest_resolvable_version)
      latest_version
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    context "for a dependency from the master source" do
      xit { is_expected.to eq(Pod::Version.new("3.0.1")) }

      context "with a version conflict at the latest version" do
        let(:podfile_content) do
          fixture("cocoapods", "podfiles", "version_conflict")
        end
        let(:lockfile_content) do
          fixture("cocoapods", "lockfiles", "version_conflict")
        end

        it { is_expected.to eq(Pod::Version.new("3.5.1")) }
      end
    end

    context "for a dependency with a git source" do
      let(:podfile_content) { fixture("cocoapods", "podfiles", "git_source") }
      let(:lockfile_content) { fixture("cocoapods", "lockfiles", "git_source") }

      it { is_expected.to be_nil }
    end

    context "for a dependency file with a specified source repo" do
      before do
        specs_url =
          "https://api.github.com/repos/dependabot/Specs/commits/master"
        stub_request(:get, specs_url).to_return(status: 304)
      end

      let(:podfile_content) do
        fixture("cocoapods", "podfiles", "private_source")
      end
      let(:lockfile_content) do
        fixture("cocoapods", "lockfiles", "private_source")
      end

      it { is_expected.to eq(Pod::Version.new("4.6.0")) }
    end

    context "for a dependency with a specified source repo (inline)" do
      before do
        specs_url =
          "https://api.github.com/repos/dependabot/Specs/commits/master"
        stub_request(:get, specs_url).to_return(status: 304)
      end

      let(:podfile_content) do
        fixture("cocoapods", "podfiles", "inline_source")
      end
      let(:lockfile_content) do
        fixture("cocoapods", "lockfiles", "inline_source")
      end

      it { is_expected.to eq(Pod::Version.new("4.6.0")) }
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    context "with a Podfile and a Podfile.lock" do
      xit "delegates to CocoaPods::RequirementsUpdater with the right params" do
        expect(
          Dependabot::CocoaPods::UpdateChecker::RequirementsUpdater
        ).to receive(:new).with(
          requirements: requirements,
          existing_version: "3.0.0",
          latest_version: instance_of(String),
          latest_resolvable_version: instance_of(String)
        ).and_call_original

        expect(updated_requirements.count).to eq(1)
        expect(updated_requirements.first[:requirement]).to start_with("~>")
      end
    end

    context "with only a Podfile" do
      let(:dependency_files) { [podfile] }
      it "raises" do
        # TODO: Extend functionality to match Ruby
        expect { updated_requirements }.to raise_error(/No Podfile.lock!/)
      end
    end
  end
end
