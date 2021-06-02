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

    context "with a private module" do
      let(:files) { project_dependency_files("private_module") }

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

    context "with a private provider" do
      let(:files) { project_dependency_files("private_provider") }

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
      let(:files) { project_dependency_files("git_tags_011") }
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
      let(:files) { project_dependency_files("git_tags_012") }
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
        let(:files) { project_dependency_files("git_tags_011") }

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
        let(:files) { project_dependency_files("git_tags_012") }

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
        let(:files) { project_dependency_files("hcl2") }

        it "shows no updates" do
          expect { subject }.to raise_error do |error|
            expect(error.message).to eq("Content didn't change!")
          end
        end
      end

      context "with a legacy registry dependency" do
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
            <<~DEP
              module "consul" {
                source = "hashicorp/consul/aws"
                version = "0.3.1"
            DEP
          )
        end
      end

      context "with an hcl2-based registry dependency" do
        let(:files) { project_dependency_files("registry_012") }
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

    context "with an hcl-based terragrunt file" do
      let(:files) { project_dependency_files("terragrunt_hcl") }

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
      let(:files) { project_dependency_files("registry_provider") }

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
      let(:files) { project_dependency_files("registry_provider_compound_local_name") }
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
      let(:files) { project_dependency_files("versions_file") }
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

    context "using versions.tf with a lockfile present" do
      let(:files) { project_dependency_files("lockfile") }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: ".terraform.lock.hcl",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: ".terraform.lock.hcl",
              source: {
                type: "lockfile",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: ".terraform.lock.hcl",
              source: {
                type: "lockfile",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            package_manager: "terraform"
          ),
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
                  version = ">= 3.0.0"
                }

                aws = {
                  source  = "hashicorp/aws"
                  version = ">= 3.37.0"
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
              version     = "3.43.0"
              constraints = ">= 3.37.0"
              hashes = [
                "h1:mXkfjIt8kZLnCUT3ej118IMCO6aKZgHjszO/NY4Zji8=",
                "zh:1496d971301216bfd27aada08f83315748972a50782c3c7a998212d733a8bd4f",
                "zh:3f43fd130eaf6ff82d713add40d38a526e978975e9517defabb32fe056a32371",
                "zh:52db549bf4d77235beb01c7bba72d577aa141a812cc1045a2808b40d2262fc3d",
                "zh:5ebdcedc4057d65e2d5689d15534eb8b4d175d8138952a298fba1c3e881c01c5",
                "zh:6264aacffd2caf82eabde2f3298cfed44377a2839dd88c67c860b83589c15129",
                "zh:759a6993c6692fd19ae83add4fd11c6be4e74adb5e7a02baff278386d4a89990",
                "zh:8a5975e90215a6c7af4eddf6fcdffb8e4aab4ff7885409728d78fff6c9e37235",
                "zh:8dd00c37cf496487066129ed19a0f7eae090cef333251789d945bc35c1723ab6",
                "zh:a0b615859497deeb95d09336a4a0c87e3687092188950b029434f742928fd299",
                "zh:e7d588099ec1868fd419cce7dc54c717816d3cb2206cc9564b6ace2a82d14f79",
                "zh:faf8443d3f87fc41d20a5867c5efecaa2c56d97b83c8f30c485c3b5dd4b7a226",
              ]
            }
          DEP
        )
      end

      it "does not update the http requirement in the lockfile" do

        actual_lockfile = subject.find { |file| file.name == ".terraform.lock.hcl" }

        expect(actual_lockfile.content).to include(
          <<~DEP
            provider "registry.terraform.io/hashicorp/random" {
              version     = "3.0.0"
              constraints = ">= 3.0.0"
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

    describe "for a provider with an implicit source" do
      let(:files) { project_dependency_files("provider_implicit_source") }
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

  end
end
