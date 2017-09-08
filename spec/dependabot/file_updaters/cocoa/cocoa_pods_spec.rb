# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/cocoa/cocoa_pods"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Cocoa::CocoaPods do
  it_behaves_like "a dependency file updater"

  before do
    master_url = "https://api.github.com/repos/CocoaPods/Specs/commits/master"
    stub_request(:get, master_url).to_return(status: 304)
  end

  let(:updater) do
    described_class.new(
      dependency_files: [podfile, lockfile],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:podfile) do
    Dependabot::DependencyFile.new(content: podfile_body, name: "Podfile")
  end
  let(:podfile_body) { fixture("cocoa", "podfiles", "version_specified") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Podfile.lock")
  end
  let(:lockfile_body) { fixture("cocoa", "lockfiles", "version_specified") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Alamofire",
      version: "4.0.0",
      previous_version: "3.0.0",
      requirements: [{
        requirement: "~> 4.0.0",
        file: "Podfile",
        groups: []
      }],
      previous_requirements: [{
        requirement: "~> 3.0.0",
        file: "Podfile",
        groups: []
      }],
      package_manager: "cocoapods"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated podfile" do
      subject(:updated_podfile) do
        updated_files.find { |f| f.name == "Podfile" }
      end

      context "when the full version is specified" do
        let(:podfile_body) { fixture("cocoa", "podfiles", "version_specified") }
        its(:content) { is_expected.to include "'Alamofire', '~> 4.0.0'" }
        its(:content) { is_expected.to include "'Nimble', '~> 2.0.0'" }
      end

      context "when the version is not specified" do
        let(:podfile_body) do
          fixture("cocoa", "podfiles", "version_not_specified")
        end
        its(:content) { is_expected.to include "'Alamofire'\n" }
        its(:content) { is_expected.to include "'Nimble'\n" }
      end
    end

    describe "the updated lockfile" do
      subject(:file) { updated_files.find { |f| f.name == "Podfile.lock" } }

      context "when the old Podfile specified the version" do
        let(:podfile_body) { fixture("cocoa", "podfiles", "version_specified") }

        it "locks the updated pod to the latest version" do
          expect(file.content).to include "Alamofire (4.0.1)"
        end

        it "doesn't change the version of the other (also outdated) pod" do
          expect(file.content).to include "Nimble (2.0.0)"
        end
      end

      context "with a private source" do
        before do
          specs_url =
            "https://api.github.com/repos/dependabot/Specs/commits/master"
          stub_request(:get, specs_url).to_return(status: 304)
        end

        let(:podfile_body) { fixture("cocoa", "podfiles", "private_source") }

        it "locks the updated pod to the latest version" do
          expect(file.content).to include "Alamofire (4.3.0)"
        end
      end

      context "with a git source for one of the other dependencies" do
        let(:podfile_body) { fixture("cocoa", "podfiles", "git_source") }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "Nimble",
            version: "6.0.0",
            previous_version: "3.0.0",
            requirements: [{
              requirement: "~> 6.0.0",
              file: "Podfile",
              groups: []
            }],
            previous_requirements: [{
              requirement: "~> 3.0.0",
              file: "Podfile",
              groups: []
            }],
            package_manager: "cocoapods"
          )
        end

        it "locks the updated pod to the latest version" do
          expect(file.content).to include "Nimble (6.0.1)"
        end

        it "leaves the other (git referencing) pod alone" do
          expect(file.content).
            to include "Alamofire: 1f72088aff8f6b40828dadd61be2e9a31beca01e"
        end

        it "generates the correct podfile checksum" do
          expect(file.content).
            to include "CHECKSUM: 2db781eacbb9b29370b899ba5cd95a2347a63bd4"
        end

        it "doesn't leave details of the access token in the lockfile" do
          expect(file.content).to_not include "x-oauth-basic"
        end
      end
    end
  end
end
