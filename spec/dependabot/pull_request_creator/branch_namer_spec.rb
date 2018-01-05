# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/branch_namer"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer do
  subject(:namer) do
    described_class.new(dependencies: [dependency], files: files)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ]
    )
  end
  let(:files) { [gemfile, gemfile_lock] }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock")
    )
  end

  describe "#new_branch_name" do
    subject(:new_branch_name) { namer.new_branch_name }
    it { is_expected.to eq("dependabot/bundler/business-1.5.0") }

    context "with directory" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("ruby", "gemfiles", "Gemfile"),
          directory: "directory"
        )
      end
      let(:gemfile_lock) do
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("ruby", "lockfiles", "Gemfile.lock"),
          directory: "directory"
        )
      end

      it { is_expected.to eq("dependabot/bundler/directory/business-1.5.0") }
    end

    context "with multiple dependencies" do
      let(:namer) do
        described_class.new(dependencies: [dependency, dep2], files: files)
      end
      let(:dep2) do
        Dependabot::Dependency.new(
          name: "statesman",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it { is_expected.to eq("dependabot/bundler/business-and-statesman") }
    end

    context "with a : in the name" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "com.google.guava:guava",
          version: "23.6-jre",
          previous_version: "23.3-jre",
          package_manager: "java",
          requirements: [
            {
              file: "pom.xml",
              requirement: "23.6-jre",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "pom.xml",
              requirement: "23.3-jre",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it "replaces the colon with a hyphen" do
        is_expected.to eq("dependabot/java/com.google.guava-guava-23.6-jre")
      end
    end
  end
end
