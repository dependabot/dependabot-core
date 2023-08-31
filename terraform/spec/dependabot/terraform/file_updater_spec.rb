# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/terraform/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Terraform::FileUpdater do
  it_behaves_like "a dependency file updater"

  subject(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end

  let(:project_name) { "" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  let(:files) { project_dependency_files(project_name) }
  let(:dependencies) { [] }
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  describe "#updated_dependency_files" do
    subject { updater.updated_dependency_files }

    context "with a private module" do
      let(:project_name) { "private_module" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "example-org-5d3190/s3-webapp/aws",
            version: "1.0.1",
            previous_version: "1.0.0",
            requirements: [{
              requirement: "1.0.1",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the private module version" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(<<~HCL)
          module "s3-webapp" {
            source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
            version = "1.0.1"
          }
        HCL
      end
    end

    context "with a private module with v prefix" do
      let(:project_name) { "private_module_with_v_prefix" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "example-org-5d3190/s3-webapp/aws",
            version: "2.0.0",
            previous_version: "v1.0.0",
            requirements: [{
              requirement: "2.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "v1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the private module version and drops the v prefix" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(<<~HCL)
          module "s3-webapp" {
            source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
            version = "2.0.0"
          }
        HCL
      end
    end

    context "with private modules with different versions" do
      let(:project_name) { "private_modules_with_different_versions" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "example-org-5d3190/s3-webapp/aws",
            version: "0.11.0",
            previous_version: "0.9.1",
            requirements: [{
              requirement: "0.11.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }, {
              requirement: "0.11.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "0.9.1",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }, {
              requirement: "0.11.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates all private modules versions" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(<<~HCL)
          module "s3-webapp-first" {
            source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
            version = "0.11.0"
          }

          module "s3-webapp-second" {
            source  = "app.terraform.io/example-org-5d3190/s3-webapp/aws"
            version = "0.11.0"
          }
        HCL
      end
    end

    context "with a private provider" do
      let(:project_name) { "private_provider" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "namespace/name",
            version: "1.0.1",
            previous_version: "1.0.0",
            requirements: [{
              requirement: "1.0.1",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.example.org",
                module_identifier: "namespace/name"
              }
            }],
            previous_requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.example.org",
                module_identifier: "namespaces/name"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the private module version" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(<<~HCL)
          terraform {
            required_providers {
              example = {
                source  = "registry.example.org/namespace/name"
                version = "1.0.1"
              }
            }
          }
        HCL
      end
    end

    context "with a valid legacy dependency file" do
      let(:project_name) { "git_tags_011" }
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

    context "with a valid HCL2 dependency file" do
      let(:project_name) { "git_tags_012" }
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

      context "with a legacy git dependency" do
        let(:project_name) { "git_tags_011" }

        it "updates the requirement" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            <<~DEP
              module "origin_label" {
                source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.4.1"
            DEP
          )
        end

        it "doesn't update the duplicate" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            <<~DEP
              module "duplicate_label" {
                source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
            DEP
          )
        end
      end

      context "with an hcl2-based git dependency" do
        let(:project_name) { "git_tags_012" }

        it "updates the requirement" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            <<~DEP
              module "origin_label" {
                source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.4.1"
            DEP
          )
        end

        it "doesn't update the duplicate" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            <<~DEP
              module "duplicate_label" {
                source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.3.7"
            DEP
          )
        end
      end

      context "with an up-to-date hcl2-based git dependency" do
        let(:project_name) { "hcl2" }

        it "shows no updates" do
          expect { subject }.to raise_error do |error|
            expect(error.message).to eq("Content didn't change!")
          end
        end
      end

      context "with a legacy registry dependency" do
        let(:project_name) { "registry" }
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
            <<~DEP
              module "consul" {
                source = "hashicorp/consul/aws"
                version = "0.3.1"
            DEP
          )
        end
      end

      context "with a legacy registry dependency with v prefix" do
        let(:project_name) { "registry_with_v_prefix" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "hashicorp/consul/aws",
              version: "0.3.1",
              previous_version: "v0.1.0",
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
                requirement: "v0.1.0",
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

        it "updates the requirement and drops the v prefix" do
          updated_file = subject.find { |file| file.name == "main.tf" }

          expect(updated_file.content).to include(
            <<~DEP
              module "consul" {
                source = "hashicorp/consul/aws"
                version = "0.3.1"
            DEP
          )
        end
      end

      context "with an hcl2-based registry dependency" do
        let(:project_name) { "registry_012" }
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
            <<~DEP
              module "consul" {
                source  = "hashicorp/consul/aws"
                version = "0.3.1"
            DEP
          )
        end
      end
    end

    context "with an hcl2-based registry dependency with a v prefix" do
      let(:project_name) { "registry_012_with_v_prefix" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/consul/aws",
            version: "0.3.1",
            previous_version: "v0.1.0",
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
              requirement: "v0.1.0",
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

      it "updates the requirement and drops the v prefix" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            module "consul" {
              source  = "hashicorp/consul/aws"
              version = "0.3.1"
          DEP
        )
      end
    end

    context "with an hcl-based terragrunt file" do
      let(:project_name) { "terragrunt_hcl" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "gruntwork-io/modules-example",
            version: "0.0.5",
            previous_version: "0.0.2",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "terragrunt.hcl",
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
              file: "terragrunt.hcl",
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
        updated_file = subject.find { |file| file.name == "terragrunt.hcl" }

        expect(updated_file.content).to include(
          <<~DEP
            source = "git::git@github.com:gruntwork-io/modules-example.git//consul?ref=v0.0.5"
          DEP
        )
      end
    end

    context "with a required provider" do
      let(:project_name) { "registry_provider" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.40.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.40.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_version = ">= 0.12"

              required_providers {
                http = {
                  source  = "hashicorp/http"
                  version = "~> 2.0"
                }

                aws = {
                  source  = "hashicorp/aws"
                  version = "3.40.0"
          DEP
        )
      end
    end

    context "with a required provider block with multiple versions" do
      let(:project_name) { "registry_provider_compound_local_name" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/http",
            version: "3.0",
            previous_version: "2.0",
            requirements: [{
              requirement: "3.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/http"
              }
            }],
            previous_requirements: [{
              requirement: "2.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/http"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_providers {
                hashicorp-http = {
                  source  = "hashicorp/http"
                  version = "3.0"
                }
                mycorp-http = {
                  source  = "mycorp/http"
                  version = "1.0"
          DEP
        )
      end
    end

    context "with a versions file" do
      let(:project_name) { "versions_file" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/random",
            version: "3.1.0",
            previous_version: "3.0.0",
            requirements: [{
              requirement: "3.1.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/random"
              }
            }],
            previous_requirements: [{
              requirement: "3.0.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/random"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement" do
        updated_file = subject.find { |file| file.name == "versions.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_providers {
                random = {
                  source  = "hashicorp/random"
                  version = ">= 3.1.0"
          DEP
        )
      end
    end

    context "updating an up-to-date terraform project with a lockfile" do
      let(:project_name) { "up-to-date_lockfile" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.45.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: ">= 3.37.0, < 3.46.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: ">= 3.37.0, < 3.46.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "raises an error" do
        expect { subject }.to raise_error do |error|
          expect(error.message).to eq("No files changed!")
        end
      end
    end

    context "using versions.tf with a lockfile present" do
      let(:project_name) { "lockfile" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "does not update requirements in the `versions.tf` file" do
        updated_file = files.find { |file| file.name == "versions.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_providers {
                random = {
                  source  = "hashicorp/random"
                  version = "3.0.0"
                }

                aws = {
                  source  = "hashicorp/aws"
                  version = ">= 3.37.0, < 3.46.0"
                }
              }
            }
          DEP
        )
      end

      it "updates the aws requirement in the lockfile" do
        actual_lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(actual_lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/aws" {
              version     = "3.45.0"
              constraints = ">= 3.42.0, < 3.46.0"
          DEP
        )
      end

      it "does not update the http requirement in the lockfile" do
        actual_lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(actual_lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/random" {
              version     = "3.0.0"
              constraints = "3.0.0"
              hashes = [
                "h1:yhHJpb4IfQQfuio7qjUXuUFTU/s+ensuEpm23A+VWz0=",
                "zh:0fcb00ff8b87dcac1b0ee10831e47e0203a6c46aafd76cb140ba2bab81f02c6b",
                "zh:123c984c0e04bad910c421028d18aa2ca4af25a153264aef747521f4e7c36a17",
                "zh:287443bc6fd7fa9a4341dec235589293cbcc6e467a042ae225fd5d161e4e68dc",
                "zh:2c1be5596dd3cca4859466885eaedf0345c8e7628503872610629e275d71b0d2",
                "zh:684a2ef6f415287944a3d966c4c8cee82c20e393e096e2f7cdcb4b2528407f6b",
                "zh:7625ccbc6ff17c2d5360ff2af7f9261c3f213765642dcd84e84ae02a3768fd51",
                "zh:9a60811ab9e6a5bfa6352fbb943bb530acb6198282a49373283a8fa3aa2b43fc",
                "zh:c73e0eaeea6c65b1cf5098b101d51a2789b054201ce7986a6d206a9e2dacaefd",
                "zh:e8f9ed41ac83dbe407de9f0206ef1148204a0d51ba240318af801ffb3ee5f578",
                "zh:fbdd0684e62563d3ac33425b0ac9439d543a3942465f4b26582bcfabcb149515",
              ]
            }
          DEP
        )
      end
    end

    context "using versions.tf with a lockfile with multiple platforms present" do
      let(:project_name) { "lockfile_multiple_platforms" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "does not update requirements in the `versions.tf` file" do
        updated_file = files.find { |file| file.name == "versions.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_providers {
                random = {
                  source  = "hashicorp/random"
                  version = "3.0.0"
                }

                aws = {
                  source  = "hashicorp/aws"
                  version = ">= 3.37.0, < 3.46.0"
                }
              }
            }
          DEP
        )
      end

      it "updates the aws requirement in the lockfile" do
        actual_lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(actual_lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/aws" {
              version     = "3.45.0"
              constraints = ">= 3.42.0, < 3.46.0"
          DEP
        )
      end

      it "does not update the http requirement in the lockfile" do
        actual_lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(actual_lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/random" {
              version     = "3.0.0"
              constraints = "3.0.0"
              hashes = [
                "h1:+JUEdzBH7Od9JKdMMAIJlX9v6P8jfbMR7V4/FKXLAgY=",
                "h1:grDzxfnOdFXi90FRIIwP/ZrCzirJ/SfsGBe6cE0Shg4=",
                "h1:yhHJpb4IfQQfuio7qjUXuUFTU/s+ensuEpm23A+VWz0=",
                "zh:0fcb00ff8b87dcac1b0ee10831e47e0203a6c46aafd76cb140ba2bab81f02c6b",
                "zh:123c984c0e04bad910c421028d18aa2ca4af25a153264aef747521f4e7c36a17",
                "zh:287443bc6fd7fa9a4341dec235589293cbcc6e467a042ae225fd5d161e4e68dc",
                "zh:2c1be5596dd3cca4859466885eaedf0345c8e7628503872610629e275d71b0d2",
                "zh:684a2ef6f415287944a3d966c4c8cee82c20e393e096e2f7cdcb4b2528407f6b",
                "zh:7625ccbc6ff17c2d5360ff2af7f9261c3f213765642dcd84e84ae02a3768fd51",
                "zh:9a60811ab9e6a5bfa6352fbb943bb530acb6198282a49373283a8fa3aa2b43fc",
                "zh:c73e0eaeea6c65b1cf5098b101d51a2789b054201ce7986a6d206a9e2dacaefd",
                "zh:e8f9ed41ac83dbe407de9f0206ef1148204a0d51ba240318af801ffb3ee5f578",
                "zh:fbdd0684e62563d3ac33425b0ac9439d543a3942465f4b26582bcfabcb149515",
              ]
            }
          DEP
        )
      end
    end

    context "when using a lockfile that requires access to an unreachable module" do
      let(:project_name) { "lockfile_unreachable_module" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: "versions.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.source).to eq("github.com/dependabot-fixtures/private-terraform-module")
        end
      end
    end

    describe "for a provider with an implicit source" do
      let(:project_name) { "provider_implicit_source" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "oci",
            version: "3.28",
            previous_version: "3.27",
            requirements: [{
              requirement: "3.28",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/oci"
              }
            }],
            previous_requirements: [{
              requirement: "3.27",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/oci"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            terraform {
              required_version = ">= 0.12"

              required_providers {
                http = {
                  source = "hashicorp/http"
                  version = "2.0.0"
                }

                oci = { // When no `source` is specified, use the implied `hashicorp/oci` source address
                  version = "3.28"
                }
          DEP
        )
      end
    end

    describe "for a nested module" do
      let(:project_name) { "nested_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "terraform-aws-modules/iam/aws",
            version: "4.1.0",
            previous_version: "4.0.0",
            requirements: [{
              requirement: "4.1.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            previous_requirements: [{
              requirement: "4.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            module "github_terraform" {
              source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
              version = "4.1.0"
            }
          DEP
        )
      end
    end

    describe "for a nested module with a v prefix" do
      let(:project_name) { "nested_modules_with_v_prefix" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "terraform-aws-modules/iam/aws",
            version: "4.1.0",
            previous_version: "v4.0.0",
            requirements: [{
              requirement: "4.1.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            previous_requirements: [{
              requirement: "v4.0.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the requirement and drops the v prefix" do
        updated_file = subject.find { |file| file.name == "main.tf" }

        expect(updated_file.content).to include(
          <<~DEP
            module "github_terraform" {
              source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
              version = "4.1.0"
            }
          DEP
        )
      end
    end

    describe "with a lockfile and modules that need to be installed" do
      let(:project_name) { "lockfile_with_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "integrations/github",
            version: "4.12.0",
            previous_version: "4.4.0",
            requirements: [{
              requirement: "4.12.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "integrations/github"
              }
            }],
            previous_requirements: [{
              requirement: "4.4.0",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "integrations/github"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the version in the lockfile" do
        lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/integrations/github" {
              version     = "4.12.0"
              constraints = "~> 4.4, <= 4.12.0"
          DEP
        )
      end
    end

    describe "when updating a module in a project with a provider lockfile" do
      let(:project_name) { "lockfile_with_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "aztfmod/caf/azurerm",
            version: "5.3.10",
            previous_version: "5.1.0",
            requirements: [{
              requirement: "5.3.10",
              groups: [],
              file: "caf_module.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: "5.1.0",
              groups: [],
              file: "caf_module.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version" do
        module_file = subject.find { |file| file.name == "caf_module.tf" }

        expect(module_file.content).to include(
          <<~DEP
            module "caf" {
              source  = "aztfmod/caf/azurerm"
              version = "5.3.10"
            }
          DEP
        )
      end
    end

    describe "when updating a module with a v prefix in a project with a provider lockfile" do
      let(:project_name) { "lockfile_with_modules_with_v_prefix" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "aztfmod/caf/azurerm",
            version: "5.3.10",
            previous_version: "v5.1.0",
            requirements: [{
              requirement: "5.3.10",
              groups: [],
              file: "caf_module.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: "v5.1.0",
              groups: [],
              file: "caf_module.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version and drops the v prefix" do
        module_file = subject.find { |file| file.name == "caf_module.tf" }

        expect(module_file.content).to include(
          <<~DEP
            module "caf" {
              source  = "aztfmod/caf/azurerm"
              version = "5.3.10"
            }
          DEP
        )
      end
    end

    describe "when updating a provider with local path modules" do
      let(:project_name) { "provider_with_local_path_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/azurerm",
            version: "2.64.0",
            previous_version: "2.63.0",
            requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version" do
        lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/azurerm" {
              version     = "2.64.0"
          DEP
        )
      end
    end

    describe "when updating provider with backend in configuration" do
      let(:project_name) { "provider_with_backend" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/azurerm",
            version: "2.64.0",
            previous_version: "2.63.0",
            requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version" do
        lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/azurerm" {
              version     = "2.64.0"
          DEP
        )
      end
    end

    describe "when updating a provider with mixed case path" do
      let(:project_name) { "provider_with_mixed_case" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Mongey/confluentcloud",
            version: "0.0.11",
            previous_version: "0.0.6",
            requirements: [{
              requirement: ">= 0.0.11, < 0.0.12",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            previous_requirements: [{
              requirement: ">= 0.0.6, < 0.0.12",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version" do
        lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/mongey/confluentcloud" {
              version     = "0.0.11"
          DEP
        )
      end
    end

    describe "when updating a provider with multiple local path modules" do
      let(:project_name) { "provider_with_multiple_local_path_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Mongey/confluentcloud",
            version: "0.0.10",
            previous_version: "0.0.6",
            requirements: [{
              requirement: "0.0.10",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.10",
              groups: [],
              file: "loader/providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.10",
              groups: [],
              file: "loader/project/providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            previous_requirements: [{
              requirement: "0.0.6",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.6",
              groups: [],
              file: "loader/providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.6",
              groups: [],
              file: "loader/project/providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "updates the module version across all nested providers" do
        updated_files = subject
        lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }
        provider_files = updated_files.select { |file| file.name.end_with?(".tf") }

        expect(provider_files.count).to eq(3)
        provider_files.each do |file|
          expect(file.content).to include("version = \"0.0.10\"")
        end

        expect(lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/mongey/confluentcloud" {
              version     = "0.0.10"
          DEP
        )
      end
    end

    describe "when provider version preceeds its source" do
      let(:project_name) { "provider_version_preceed" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/azurerm",
            version: "3.40.0",
            previous_version: "3.30.0",
            requirements: [{
              requirement: "3.40.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: "3.31.0",
              groups: [],
              file: "providers.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            package_manager: "terraform"
          )
        ]
      end

      it "parses correctly and updates the module version" do
        updated_file = subject.find { |file| file.name == "providers.tf" }
        expect(updated_file.content).to include("version = \"3.40.0\"")
      end
    end

    context "with duplicate children modules" do
      let(:project_name) { "duplicate_child_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "child_module_one/main.tf",
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
              file: "child_module_one/main.tf",
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
  end
end
