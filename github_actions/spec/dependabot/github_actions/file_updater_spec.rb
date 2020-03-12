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

      its(:content) { is_expected.to include "actions/setup-node@v1.1.0\n" }
      its(:content) { is_expected.to_not include "actions/setup-node@master" }
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
    end
  end
end
