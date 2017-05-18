# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/cocoa"
require_relative "./shared_examples_for_update_checkers"

RSpec.describe Bump::UpdateCheckers::Cocoa do
  it_behaves_like "an update checker"

  before do
    master_url = "https://api.github.com/repos/CocoaPods/Specs/commits/master"
    stub_request(:get, master_url).to_return(status: 304)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [podfile, podfile_lock],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Bump::Dependency.new(name: "Alamofire", version: "3.0.0", language: "cocoa")
  end

  let(:podfile) do
    Bump::DependencyFile.new(content: podfile_content, name: "Podfile")
  end
  let(:podfile_lock) do
    Bump::DependencyFile.new(
      content: lockfile_content,
      name: "Podfile.lock"
    )
  end
  let(:podfile_content) { fixture("cocoa", "podfiles", "version_specified") }
  let(:lockfile_content) { fixture("cocoa", "lockfiles", "version_specified") }

  describe "#latest_version" do
    subject { checker.latest_version }

    # Stubbing the CocoaPods spec repo is hard. Instead just spec that the
    # latest version is high
    it { is_expected.to be >= Gem::Version.new("4.4.0") }

    context "for a dependency with a git source" do
      let(:podfile_content) { fixture("cocoa", "podfiles", "git_source") }
      let(:lockfile_content) { fixture("cocoa", "lockfiles", "git_source") }

      it { is_expected.to be_nil }
    end

    context "for a dependency file with a specified source repo" do
      before do
        specs_url =
          "https://api.github.com/repos/dependabot/Specs/commits/master"
        stub_request(:get, specs_url).to_return(status: 304)
      end

      let(:podfile_content) { fixture("cocoa", "podfiles", "private_source") }
      let(:lockfile_content) { fixture("cocoa", "lockfiles", "private_source") }

      it { is_expected.to eq(Gem::Version.new("4.3.0")) }
    end

    context "for a dependency with a specified source repo" do
      before do
        specs_url =
          "https://api.github.com/repos/dependabot/Specs/commits/master"
        stub_request(:get, specs_url).to_return(status: 304)
      end

      let(:podfile_content) { fixture("cocoa", "podfiles", "inline_source") }
      let(:lockfile_content) { fixture("cocoa", "lockfiles", "inline_source") }

      it { is_expected.to eq(Gem::Version.new("4.3.0")) }
    end
  end
end
