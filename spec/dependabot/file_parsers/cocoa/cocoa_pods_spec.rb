# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/cocoa/cocoa_pods"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Cocoa::CocoaPods do
  it_behaves_like "a dependency file parser"

  let(:files) { [podfile, lockfile] }
  let(:podfile) do
    Dependabot::DependencyFile.new(name: "Podfile", content: podfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Podfile.lock", content: lockfile_body)
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:podfile_body) { fixture("cocoa", "podfiles", "version_specified") }
      let(:lockfile_body) { fixture("cocoa", "lockfiles", "version_specified") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq(Gem::Version.new("3.0.1")) }
      end
    end

    context "with no version specified" do
      let(:podfile_body) do
        fixture("cocoa", "podfiles", "version_not_specified")
      end
      let(:lockfile_body) do
        fixture("cocoa", "lockfiles", "version_not_specified")
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq(Gem::Version.new("3.0.1")) }
      end
    end

    context "with a version specified as between two constraints" do
      let(:podfile_body) do
        fixture("cocoa", "podfiles", "version_between_bounds")
      end
      let(:lockfile_body) { fixture("cocoa", "lockfiles", "version_specified") }

      its(:length) { is_expected.to eq(1) }
    end

    context "for a dependency with a git source" do
      let(:podfile_body) { fixture("cocoa", "podfiles", "git_source") }
      let(:lockfile_body) { fixture("cocoa", "lockfiles", "git_source") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq(Gem::Version.new("4.3.0")) }
      end
    end

    context "with development dependencies" do
      let(:podfile_body) do
        fixture("cocoa", "podfiles", "development_dependencies")
      end
      let(:lockfile_body) do
        fixture("cocoa", "lockfiles", "development_dependencies")
      end

      its(:length) { is_expected.to eq(2) }
    end
  end
end
