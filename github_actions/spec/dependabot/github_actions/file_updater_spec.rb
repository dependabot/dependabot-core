# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/github_actions/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::GithubActions::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [workflow_file] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:workflow_file) do
    Dependabot::DependencyFile.new(
      content: workflow_file_body,
      name: ".github/workflows/workflow.yml"
    )
  end
  let(:workflow_file_body) { fixture("workflow_files", "workflow.yml") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "actions/setup-node",
      version: "5273d0df9c603edc4284ac8402cf650b4f1f6686",
      previous_version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: {
          type: "git",
          url: "https://github.com/actions/setup-node",
          ref: "v1.1.0",
          branch: nil
        },
        metadata: { declaration_string: "actions/setup-node@master" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: {
          type: "git",
          url: "https://github.com/actions/setup-node",
          ref: "master",
          branch: nil
        },
        metadata: { declaration_string: "actions/setup-node@master" }
      }],
      package_manager: "github_actions"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated workflow file" do
      subject(:updated_workflow_file) do
        updated_files.find { |f| f.name == ".github/workflows/workflow.yml" }
      end

      its(:content) do
        is_expected.to include "\"actions/setup-node@v1.1.0\"\n"
        is_expected.to_not include "\"actions/setup-node@master\""
      end

      its(:content) do
        is_expected.to include "'actions/setup-node@v1.1.0'\n"
        is_expected.to_not include "'actions/setup-node@master'"
      end

      its(:content) do
        is_expected.to include "actions/setup-node@v1.1.0\n"
        is_expected.to_not include "actions/setup-node@master"
      end

      its(:content) { is_expected.to include "actions/checkout@master\n" }

      context "with a path" do
        let(:workflow_file_body) do
          fixture("workflow_files", "workflow_monorepo.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "actions/aws",
            version: "5273d0df9c603edc4284ac8402cf650b4f1f6686",
            previous_version: nil,
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/aws",
                ref: "v1.1.0",
                branch: nil
              },
              metadata: { declaration_string: "actions/aws/ec2@master" }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/aws",
                ref: "v1.1.0",
                branch: nil
              },
              metadata: { declaration_string: "actions/aws@master" }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/aws",
                ref: "master",
                branch: nil
              },
              metadata: { declaration_string: "actions/aws/ec2@master" }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/aws",
                ref: "master",
                branch: nil
              },
              metadata: { declaration_string: "actions/aws@master" }
            }],
            package_manager: "github_actions"
          )
        end

        its(:content) { is_expected.to include "actions/aws/ec2@v1.1.0\n" }
        its(:content) { is_expected.to include "actions/aws@v1.1.0\n" }
        its(:content) { is_expected.to_not include "actions/aws/ec2@master" }
        its(:content) { is_expected.to include "actions/checkout@master\n" }
      end

      context "with multiple sources" do
        let(:workflow_file_body) do
          fixture("workflow_files", "multiple_sources.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "actions/checkout",
            version: nil,
            package_manager: "github_actions",
            previous_version: nil,
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/checkout@v2.1.0" },
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "v2.1.0",
                branch: nil
              }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/checkout@master" },
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "master",
                branch: nil
              }
            }],
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/checkout@v2.2.0" },
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "v2.2.0",
                branch: nil
              }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/checkout@master" },
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "v2.2.0",
                branch: nil
              }
            }]
          )
        end

        it "updates both sources" do
          expect(subject.content).to include "actions/checkout@v2.2.0\n"
          expect(subject.content).not_to include "actions/checkout@master\n"
        end
      end

      context "with multiple sources matching major version" do
        let(:workflow_file_body) do
          fixture("workflow_files", "multiple_sources_matching_major.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "actions/cache",
            version: nil,
            package_manager: "github_actions",
            previous_version: nil,
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/cache@v1" },
              source: {
                type: "git",
                url: "https://github.com/actions/cache",
                ref: "v1",
                branch: nil
              }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/cache@v1.1.2" },
              source: {
                type: "git",
                url: "https://github.com/actions/cache",
                ref: "v1.1.2",
                branch: nil
              }
            }],
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/cache@v2" },
              source: {
                type: "git",
                url: "https://github.com/actions/cache",
                ref: "v2",
                branch: nil
              }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              metadata: { declaration_string: "actions/cache@v1.1.2" },
              source: {
                type: "git",
                url: "https://github.com/actions/cache",
                ref: "v2",
                branch: nil
              }
            }]
          )
        end

        it "updates both sources" do
          expect(subject.content).to include "actions/cache@v2 # comment"
          expect(subject.content).to match(%r{actions\/cache@v2$})
          expect(subject.content).not_to include "actions/cache@v1.1.2\n"
          expect(subject.content).not_to include "actions/cache@v2.1.2\n"
        end
      end

      context "with pinned SHA hash and version in comment" do
        let(:service_pack_url) do
          "https://github.com/actions/checkout.git/info/refs" \
            "?service=git-upload-pack"
        end
        before do
          stub_request(:get, service_pack_url).
            to_return(
              status: 200,
              body: fixture("git", "upload_packs", "checkout"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        let(:workflow_file_body) do
          fixture("workflow_files", "pinned_sources_version_comments.yml")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "actions/checkout",
            version: "2.2.0",
            package_manager: "github_actions",
            previous_version: "2.1.0",
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "01aecccf739ca6ff86c0539fbc67a7a5007bbc81",
                branch: nil
              },
              metadata: { declaration_string: "actions/checkout@01aecccf739ca6ff86c0539fbc67a7a5007bbc81" }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "v2.1.0",
                branch: nil
              },
              metadata: { declaration_string: "actions/checkout@v2.1.0" }
            }],
            requirements: [{
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "aabbfeb2ce60b5bd82389903509092c4648a9713",
                branch: nil
              },
              metadata: { declaration_string: "actions/checkout@aabbfeb2ce60b5bd82389903509092c4648a9713" }
            }, {
              requirement: nil,
              groups: [],
              file: ".github/workflows/workflow.yml",
              source: {
                type: "git",
                url: "https://github.com/actions/checkout",
                ref: "v2.2.0",
                branch: nil
              },
              metadata: { declaration_string: "actions/checkout@v2.2.0" }
            }]
          )
        end

        it "updates SHA version" do
          old_sha = dependency.previous_requirements.first.dig(:source, :ref)
          expect(subject.content).to include "#{dependency.name}@#{dependency.requirements.first.dig(:source, :ref)}"
          expect(subject.content).not_to match(/#{old_sha}\s+#.*#{dependency.previous_version}/)
        end
        it "updates version comment" do
          new_sha = dependency.requirements.first.dig(:source, :ref)
          expect(subject.content).not_to match(/@#{new_sha}\s+#.*#{dependency.previous_version}\s*$/)

          expect(subject.content).to include "# v#{dependency.version}"
          expect(subject.content).to include "# #{dependency.version}"
          expect(subject.content).to include "# @v#{dependency.version}"
          expect(subject.content).to include "# pin @v#{dependency.version}"
          expect(subject.content).to include "# tag=v#{dependency.version}"
        end
        it "doesn't update version comments when @ref is not a SHA" do
          old_version = dependency.previous_requirements[1].dig(:source, :ref)
          expect(subject.content).not_to match(/@#{old_version}\s+#.*#{dependency.version}/)
        end
        it "doesn't update version comments in the middle of sentences" do
          # rubocop:disable Layout/LineLength
          expect(subject.content).to include "Versions older than v#{dependency.previous_version} have a security vulnerability"
          expect(subject.content).not_to include "Versions older than v#{dependency.version} have a security vulnerability"
          # rubocop:enable Layout/LineLength
        end
      end
    end
  end
end
