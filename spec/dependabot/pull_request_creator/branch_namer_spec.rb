# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/branch_namer"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer do
  subject(:namer) do
    described_class.new(
      dependencies: dependencies,
      files: files,
      target_branch: target_branch
    )
  end

  let(:dependencies) { [dependency] }
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
  let(:target_branch) { nil }

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

    context "with a target branch" do
      let(:target_branch) { "my-branch" }

      it { is_expected.to eq("dependabot/bundler/my-branch/business-1.5.0") }
    end

    context "with multiple dependencies" do
      let(:dependencies) { [dependency, dep2] }
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

      context "for a java update" do
        let(:files) { [pom] }
        let(:pom) do
          Dependabot::DependencyFile.new(name: "pom.xml", content: pom_content)
        end
        let(:pom_content) do
          fixture("java", "poms", "property_pom.xml").
            gsub("4.3.12.RELEASE", "23.6-jre")
        end
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "org.springframework:spring-beans",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              package_manager: "maven"
            ),
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
              version: "23.6-jre",
              previous_version: "4.3.12.RELEASE",
              requirements: [
                {
                  file: "pom.xml",
                  requirement: "23.6-jre",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              previous_requirements: [
                {
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }
              ],
              package_manager: "maven"
            )
          ]
        end

        it { is_expected.to eq("dependabot/maven/springframework.version") }
      end
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
        expect(new_branch_name).
          to eq("dependabot/java/com.google.guava-guava-23.6-jre")
      end
    end

    context "with SHA-1 versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
          previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
          package_manager: "bundler",
          requirements: [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: new_ref
              }
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: old_ref
              }
            }
          ]
        )
      end
      let(:new_ref) { nil }
      let(:old_ref) { nil }

      it "truncates the version" do
        expect(new_branch_name).to eq("dependabot/bundler/business-cff701b")
      end

      context "due to a ref change" do
        let(:new_ref) { "v1.1.0" }
        let(:old_ref) { "v1.0.0" }

        it "includes the ref rather than the commit" do
          expect(new_branch_name).to eq("dependabot/bundler/business-v1.1.0")
        end
      end
    end
  end
end
