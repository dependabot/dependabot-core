# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/terraform/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Terraform::FileUpdater do
  it_behaves_like "a dependency file updater"

  subject(:updater) do
    described_class.new(dependency_files: files, dependencies: dependencies, credentials: credentials)
  end

  let(:files) { [] }
  let(:dependencies) { [] }
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  describe "#updated_dependency_files" do
    subject { updater.updated_dependency_files }

    context "when updating to the latest version of the aws provider" do
      let(:files) { project_dependency_files("aws") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "aws",
            version: "3.38.0",
            previous_version: "3.27.0",
            requirements: [],
            previous_requirements: [],
            package_manager: "terraform"
          )
        ]
      end

      specify { expect(subject.count).to eql(1) }

      it "updates the `.terraform.lock.hcl` file" do
        lock_file = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(lock_file.content).to eql(<<~LOCKFILE)
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "3.38.0"
  constraints = "~> 3.27"
  hashes = [
    "h1:ARuS11ThIcUfmAQKWNXGPLOa1GheaIwkeCnMh9Mjvao=",
    "zh:20476d4c1b0c0efc55226bcbd85fbd948638fd9860a0edcdb7875cbb2b449e46",
    "zh:7102622e6549cc3fc46b9ad68cbf4c50b162ce1013d4da817d05d1edf1f12fae",
    "zh:74ff7f1610065e14c043cd9d74b3d5e0de4474f09a1a81e0b126b920b5cf6a27",
    "zh:800e1b168149d507d23845f7a8b7e598c7dc16d2ee0f47848cf85d3e7458884f",
    "zh:81ac3c68d6230b77740ca367e0c05a32ebb9be0fe5478c836573218a84eb3e46",
    "zh:86536598796ba65539816f08351ac0ab32988ab84fa8f100049579996fafc800",
    "zh:b9985c64f0f0b5bafb7067a60381fd807f7c3dd952c5d9f531385e464867bdd5",
    "zh:c19c692896469724c6320fa7d87532ec3935e14e0e0fa0a8a0f1cf28ae7a0b0a",
    "zh:cb8b14f246953a275ada562f5275a0d1a4938b7d20597e62fabe264012410f53",
    "zh:cdbfa0ad87ff4d7451cfb89e53692a651d4c9cadece6845e60d986fd454b52b3",
    "zh:ed5c4c8ae5adda37942bb15ef058c0811a95cb4c87259ae822627756dcb90efc",
  ]
}
        LOCKFILE
      end
    end

    context "with a valid dependency file" do
      let(:files) { project_dependency_files("git_tags") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-null-label.git",
                branch: nil,
                ref: "tags/0.4.1"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-null-label.git",
                branch: nil,
                ref: "tags/0.3.7"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      specify { expect(subject).to all(be_a(Dependabot::DependencyFile)) }
      specify { expect(subject.length).to eq(1) }
    end

    describe "the updated file" do
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-null-label.git",
                branch: nil,
                ref: "tags/0.4.1"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-null-label.git",
                branch: nil,
                ref: "tags/0.3.7"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      context "with a git dependency" do
        let(:files) { project_dependency_files("git_tags") }

        it "updates the requirement" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            "module \"origin_label\" {\n"\
            "  source     = \"git::https://github.com/cloudposse/"\
            "terraform-null-label.git?ref=tags/0.4.1\"\n"
          )
        end

        it "doesn't update the duplicate" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            "module \"duplicate_label\" {\n"\
            "  source     = \"git::https://github.com/cloudposse/"\
            "terraform-null-label.git?ref=tags/0.3.7\"\n"
          )
        end
      end

      context "with a registry dependency" do
        let(:files) { project_dependency_files("registry") }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "hashicorp/consul/aws",
              version: "0.3.1",
              previous_version: "0.1.0",
              requirements: [{
                requirement: "0.3.1",
                groups: [],
                file: "main.tf",
                source: {
                  type: "registry",
                  registry_hostname: "registry.terraform.io",
                  module_identifier: "hashicorp/consul/aws"
                }
              }],
              previous_requirements: [{
                requirement: "0.1.0",
                groups: [],
                file: "main.tf",
                source: {
                  type: "registry",
                  registry_hostname: "registry.terraform.io",
                  module_identifier: "hashicorp/consul/aws"
                }
              }],
              package_manager: "terraform"
            )
          ]
        end

        it "updates the requirement" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            "module \"consul\" {\n"\
            "  source = \"hashicorp/consul/aws\"\n"\
            "  version = \"0.3.1\"\n"\
            "}"
          )
        end
      end

      context "with a terragrunt file" do
        let(:files) { project_dependency_files("terragrunt") }

        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "gruntwork-io/modules-example",
              version: "0.0.5",
              previous_version: "0.0.2",
              requirements: [{
                requirement: nil,
                groups: [],
                file: "main.tfvars",
                source: {
                  type: "git",
                  url: "git@github.com:gruntwork-io/modules-example.git",
                  branch: nil,
                  ref: "v0.0.5"
                }
              }],
              previous_requirements: [{
                requirement: nil,
                groups: [],
                file: "main.tfvars",
                source: {
                  type: "git",
                  url: "git@github.com:gruntwork-io/modules-example.git",
                  branch: nil,
                  ref: "v0.0.2"
                }
              }],
              package_manager: "terraform"
            )
          ]
        end

        it "updates the requirement" do
          updated_file = subject.find { |file| file.name == "main.tfvars" }

          expect(updated_file.content).to include(
            "source = \"git::git@github.com:gruntwork-io/modules-example.git//"\
            "consul?ref=v0.0.5\""
          )
        end
      end
    end
  end
end
