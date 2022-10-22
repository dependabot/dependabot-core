# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cocoapods/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::CocoaPods::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [podfile, lockfile] }
  let(:podfile) do
    Dependabot::DependencyFile.new(name: "Podfile", content: podfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Podfile.lock", content: lockfile_body)
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "version_specified")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "version_specified")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "~> 3.0.0",
            file: "Podfile",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq("3.0.1") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with no version specified" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "version_not_specified")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "version_not_specified")
      end

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Podfile",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq("3.0.1") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a sub-dependency" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "subdependency")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "subdependency")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the last dependency" do
        subject { dependencies.last }
        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq("3.5.1") }
        its(:requirements) { is_expected.to eq([]) }
      end
    end

    context "with a version specified as between two constraints" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "version_between_bounds")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "version_specified")
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "for a dependency with a git source" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "git_source")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "git_source")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Podfile",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/Alamofire/Alamofire.git",
              branch: nil,
              ref: "4.3.0"
            }
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:version) { is_expected.to eq("4.3.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "for a dependency with a git source and branch specified" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "git_source_branch")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "git_source_branch")
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: ">= 0",
            file: "Podfile",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/Alamofire/Alamofire.git",
              branch: "hotfix",
              ref: nil
            }
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("Alamofire") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with development dependencies" do
      let(:podfile_body) do
        fixture("cocoapods", "podfiles", "development_dependencies")
      end
      let(:lockfile_body) do
        fixture("cocoapods", "lockfiles", "development_dependencies")
      end

      its(:length) { is_expected.to eq(2) }
    end
  end
end
