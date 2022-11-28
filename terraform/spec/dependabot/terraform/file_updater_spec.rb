# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/terraform/file_updater"
require "json"
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

  let(:file_format) { "tf" }
  let(:file_extension) do
    case file_format
    when "tf"
      ".tf"
    when "json"
      ".tf.json"
    end
  end
  let(:file_name_base) { "" }
  let(:file_name) { file_name_base + file_extension }

  let(:project_name) do
    case file_format
    when "tf"
      project_name_base
    when "json"
      project_name_base + "_json"
    end
  end

  let(:files) { project_dependency_files(project_name) }
  let(:file) { files.find { |file| file.name == file_name } }

  let(:updated_file) { updated_files.find { |file| file.name == file_name } }
  let(:updated_file_json) { JSON.parse(updated_file.content) }
  let(:updated_files_expected) { project_dependency_files_updated_expected(project_name) }
  let(:updated_file_expected) { updated_files_expected.find { |file| file.name == file_name } }
  let(:updated_file_expected_json) { JSON.parse(updated_file_expected.content) }

  let(:dependencies) { [] }
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:file_name_base) { "main" }

    context "with a private module" do
      let(:project_name_base) { "private_module" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "example-org-5d3190/s3-webapp/aws",
            version: "1.0.1",
            previous_version: "1.0.0",
            requirements: [{
              requirement: "1.0.1",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the private module version" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the private module version" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "with a private module with v prefix" do
      let(:project_name_base) { "private_module_with_v_prefix" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "example-org-5d3190/s3-webapp/aws",
            version: "2.0.0",
            previous_version: "v1.0.0",
            requirements: [{
              requirement: "2.0.0",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "app.terraform.io",
                module_identifier: "example-org-5d3190/s3-webapp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "v1.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the private module version and drops the v prefix" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the private module version and drops the v prefix" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
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
      let(:project_name_base) { "private_provider" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "namespace/name",
            version: "1.0.1",
            previous_version: "1.0.0",
            requirements: [{
              requirement: "1.0.1",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.example.org",
                module_identifier: "namespace/name"
              }
            }],
            previous_requirements: [{
              requirement: "1.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the private module version" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the private module version" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "with a valid legacy dependency file" do
      let(:project_name_base) { "git_tags_011" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: file_name,
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
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        specify { expect(updated_files).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(updated_files.length).to eq(1) }
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        specify { expect(updated_files).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(updated_files.length).to eq(1) }
      end
    end

    context "with a valid HCL2 dependency file" do
      let(:project_name_base) { "git_tags_012" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: file_name,
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
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        specify { expect(updated_files).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(updated_files.length).to eq(1) }
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        specify { expect(updated_files).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(updated_files.length).to eq(1) }
      end
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
              file: file_name,
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
              file: file_name,
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
        let(:project_name_base) { "git_tags_011" }
        let(:origin_label_expected) do
          updated_files_expected.find { |file| file.name == "origin_label_expected" + file_extension }
        end
        let(:duplicate_label_expected) do
          updated_files_expected.find { |file| file.name == "duplicate_label_expected" + file_extension }
        end

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "updates the requirement" do
            expect(updated_file.content).to include(origin_label_expected.content)
          end
          it "doesn't update the duplicate" do
            expect(updated_file.content).to include(duplicate_label_expected.content)
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "updates the requirement" do
            expect(updated_file_json["module"]["origin_label"]).to(
              eq(JSON.parse(origin_label_expected.content)["origin_label"])
            )
          end
          it "doesn't update the duplicate" do
            expect(updated_file_json["module"]["duplicate_label"]).to(
              eq(JSON.parse(duplicate_label_expected.content)["duplicate_label"])
            )
          end
        end
      end

      context "with an hcl2-based git dependency" do
        let(:project_name_base) { "git_tags_012" }
        let(:origin_label_expected) do
          updated_files_expected.find { |file| file.name == "origin_label_expected" + file_extension }
        end
        let(:duplicate_label_expected) do
          updated_files_expected.find { |file| file.name == "duplicate_label_expected" + file_extension }
        end

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "updates the requirement" do
            expect(updated_file.content).to include(origin_label_expected.content)
          end
          it "doesn't update the duplicate" do
            expect(updated_file.content).to include(duplicate_label_expected.content)
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "updates the requirement" do
            expect(updated_file_json["module"]["origin_label"]).to(
              eq(JSON.parse(origin_label_expected.content)["origin_label"])
            )
          end
          it "doesn't update the duplicate" do
            expect(updated_file_json["module"]["duplicate_label"]).to(
              eq(JSON.parse(duplicate_label_expected.content)["duplicate_label"])
            )
          end
        end
      end

      context "with an up-to-date hcl2-based git dependency" do
        let(:project_name_base) { "hcl2" }

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "shows no updates" do
            expect { updated_files }.to raise_error do |error|
              expect(error.message).to eq("Content didn't change!")
            end
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "shows no updates" do
            expect { updated_files }.to raise_error do |error|
              expect(error.message).to eq("Content didn't change!")
            end
          end
        end
      end

      context "with a legacy registry dependency" do
        let(:project_name_base) { "registry" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "hashicorp/consul/aws",
              version: "0.3.1",
              previous_version: "0.1.0",
              requirements: [{
                requirement: "0.3.1",
                groups: [],
                file: file_name,
                source: {
                  type: "registry",
                  registry_hostname: "registry.terraform.io",
                  module_identifier: "hashicorp/consul/aws"
                }
              }],
              previous_requirements: [{
                requirement: "0.1.0",
                groups: [],
                file: file_name,
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

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "updates the requirement" do
            expect(updated_file.content).to include(updated_file_expected.content)
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "updates the requirement" do
            expect(updated_file_json).to eq(updated_file_expected_json)
          end
        end
      end

      context "with a legacy registry dependency with v prefix" do
        let(:project_name_base) { "registry_with_v_prefix" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "hashicorp/consul/aws",
              version: "0.3.1",
              previous_version: "v0.1.0",
              requirements: [{
                requirement: "0.3.1",
                groups: [],
                file: file_name,
                source: {
                  type: "registry",
                  registry_hostname: "registry.terraform.io",
                  module_identifier: "hashicorp/consul/aws"
                }
              }],
              previous_requirements: [{
                requirement: "v0.1.0",
                groups: [],
                file: file_name,
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

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "updates the requirement and drops the v prefix" do
            expect(updated_file.content).to include(updated_file_expected.content)
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "updates the requirement and drops the v prefix" do
            expect(updated_file_json).to eq(updated_file_expected_json)
          end
        end
      end

      context "with an hcl2-based registry dependency" do
        let(:project_name_base) { "registry_012" }
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "hashicorp/consul/aws",
              version: "0.3.1",
              previous_version: "0.1.0",
              requirements: [{
                requirement: "0.3.1",
                groups: [],
                file: file_name,
                source: {
                  type: "registry",
                  registry_hostname: "registry.terraform.io",
                  module_identifier: "hashicorp/consul/aws"
                }
              }],
              previous_requirements: [{
                requirement: "0.1.0",
                groups: [],
                file: file_name,
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

        context "with modules in hcl format" do
          let(:file_format) { "tf" }
          it "updates the requirement" do
            expect(updated_file.content).to include(updated_file_expected.content)
          end
        end
        context "with modules in json format" do
          let(:file_format) { "json" }
          it "updates the requirement" do
            expect(updated_file_json).to eq(updated_file_expected_json)
          end
        end
      end
    end

    context "with an hcl2-based registry dependency with a v prefix" do
      let(:project_name_base) { "registry_012_with_v_prefix" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/consul/aws",
            version: "0.3.1",
            previous_version: "v0.1.0",
            requirements: [{
              requirement: "0.3.1",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/consul/aws"
              }
            }],
            previous_requirements: [{
              requirement: "v0.1.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement and drops the v prefix" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement and drops the v prefix" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "with an hcl-based terragrunt file" do
      let(:project_name_base) { "terragrunt_hcl" }
      let(:file_name) { "terragrunt.hcl" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "gruntwork-io/modules-example",
            version: "0.0.5",
            previous_version: "0.0.2",
            requirements: [{
              requirement: nil,
              groups: [],
              file: file_name,
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
              file: file_name,
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
        expect(updated_file.content).to include(
          <<~DEP
            source = "git::git@github.com:gruntwork-io/modules-example.git//consul?ref=v0.0.5"
          DEP
        )
      end
    end

    context "with a required provider" do
      let(:project_name_base) { "registry_provider" }

      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.40.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.40.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "with a required provider block with multiple versions" do
      let(:project_name_base) { "registry_provider_compound_local_name" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/http",
            version: "3.0",
            previous_version: "2.0",
            requirements: [{
              requirement: "3.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/http"
              }
            }],
            previous_requirements: [{
              requirement: "2.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "with a versions file" do
      let(:project_name_base) { "versions_file" }
      let(:file_name_base) { "versions" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/random",
            version: "3.1.0",
            previous_version: "3.0.0",
            requirements: [{
              requirement: "3.1.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/random"
              }
            }],
            previous_requirements: [{
              requirement: "3.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    context "updating an up-to-date terraform project with a lockfile" do
      let(:project_name_base) { "up-to-date_lockfile" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.45.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: ">= 3.37.0, < 3.46.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: ">= 3.37.0, < 3.46.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "raises an error" do
          expect { updated_files }.to raise_error do |error|
            expect(error.message).to eq("No files changed!")
          end
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "raises an error" do
          expect { updated_files }.to raise_error do |error|
            expect(error.message).to eq("No files changed!")
          end
        end
      end
    end

    context "using versions.tf with a lockfile present" do
      let(:project_name_base) { "lockfile" }
      let(:file_name_base) { "versions" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "does not update requirements in the `versions.tf` file" do
          # the original code uses the file from "files" rather than "updated_files" here
          # not sure if this is intended, but keeping the original behavior for now
          # TODO: check this
          expect(file.content).to include(updated_file_expected.content)
        end
        it "updates the aws requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(actual_lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/aws" {
                version     = "3.45.0"
                constraints = ">= 3.42.0, < 3.46.0"
            DEP
          )
        end
        it "does not update the http requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

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
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "does not update requirements in the `versions.tf.json` file" do
          # the original code uses the file from "files" rather than "updated_files" here
          # not sure if this is intended, but keeping the original behavior for now
          # TODO: check this
          expect(JSON.parse(file.content)).to eq(updated_file_expected_json)
        end
        it "updates the aws requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(actual_lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/aws" {
                version     = "3.45.0"
                constraints = ">= 3.42.0, < 3.46.0"
            DEP
          )
        end
        it "does not update the http requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

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
    end

    context "using versions.tf with a lockfile with multiple platforms present" do
      let(:project_name_base) { "lockfile_multiple_platforms" }
      let(:file_name_base) { "versions" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "does not update requirements in the `versions.tf` file" do
          # the original code uses the file from "files" rather than "updated_files" here
          # not sure if this is intended, but keeping the original behavior for now
          # TODO: check this
          expect(file.content).to include(updated_file_expected.content)
        end
        it "updates the aws requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(actual_lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/aws" {
                version     = "3.45.0"
                constraints = ">= 3.42.0, < 3.46.0"
            DEP
          )
        end
        it "does not update the http requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

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
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "does not update requirements in the `versions.tf.json` file" do
          # the original code uses the file from "files" rather than "updated_files" here
          # not sure if this is intended, but keeping the original behavior for now
          # TODO: check this
          expect(JSON.parse(file.content)).to eq(updated_file_expected_json)
        end
        it "updates the aws requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(actual_lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/aws" {
                version     = "3.45.0"
                constraints = ">= 3.42.0, < 3.46.0"
            DEP
          )
        end
        it "does not update the http requirement in the lockfile" do
          actual_lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

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
    end

    context "when using a lockfile that requires access to an unreachable module" do
      let(:project_name_base) { "lockfile_unreachable_module" }
      let(:file_name_base) { "versions" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/aws",
            version: "3.42.0",
            previous_version: "3.37.0",
            requirements: [{
              requirement: "3.42.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }],
            previous_requirements: [{
              requirement: "3.37.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "raises a helpful error" do
          expect { updated_files }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("github.com/dependabot-fixtures/private-terraform-module")
          end
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "raises a helpful error" do
          expect { updated_files }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("github.com/dependabot-fixtures/private-terraform-module")
          end
        end
      end
    end

    describe "for a provider with an implicit source" do
      let(:project_name_base) { "provider_implicit_source" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "oci",
            version: "3.28",
            previous_version: "3.27",
            requirements: [{
              requirement: "3.28",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/oci"
              }
            }],
            previous_requirements: [{
              requirement: "3.27",
              groups: [],
              file: file_name,
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
        expect(updated_file.content).to include(updated_file_expected.content)
      end
    end

    describe "for a nested module" do
      let(:project_name_base) { "nested_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "terraform-aws-modules/iam/aws",
            version: "4.1.0",
            previous_version: "4.0.0",
            requirements: [{
              requirement: "4.1.0",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            previous_requirements: [{
              requirement: "4.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    describe "for a nested module with a v prefix" do
      let(:project_name_base) { "nested_modules_with_v_prefix" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "terraform-aws-modules/iam/aws",
            version: "4.1.0",
            previous_version: "v4.0.0",
            requirements: [{
              requirement: "4.1.0",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "iam/aws"
              }
            }],
            previous_requirements: [{
              requirement: "v4.0.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the requirement and drops the v prefix" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the requirement and drops the v prefix" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    describe "with a lockfile and modules that need to be installed" do
      let(:project_name_base) { "lockfile_with_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "integrations/github",
            version: "4.12.0",
            previous_version: "4.4.0",
            requirements: [{
              requirement: "4.12.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "integrations/github"
              }
            }],
            previous_requirements: [{
              requirement: "4.4.0",
              groups: [],
              file: file_name,
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
        lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

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
      let(:project_name_base) { "lockfile_with_modules" }
      let(:file_name_base) { "caf_module" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "aztfmod/caf/azurerm",
            version: "5.3.10",
            previous_version: "5.1.0",
            requirements: [{
              requirement: "5.3.10",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: "5.1.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    describe "when updating a module with a v prefix in a project with a provider lockfile" do
      let(:project_name_base) { "lockfile_with_modules_with_v_prefix" }
      let(:file_name_base) { "caf_module" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "aztfmod/caf/azurerm",
            version: "5.3.10",
            previous_version: "v5.1.0",
            requirements: [{
              requirement: "5.3.10",
              groups: [],
              file: file_name,
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "aztfmod/caf/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: "v5.1.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version and drops the v prefix" do
          expect(updated_file.content).to include(updated_file_expected.content)
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version and drops the v prefix" do
          expect(updated_file_json).to eq(updated_file_expected_json)
        end
      end
    end

    describe "when updating a provider with local path modules" do
      let(:project_name_base) { "provider_with_local_path_modules" }
      let(:file_name_base) { "providers" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/azurerm",
            version: "2.64.0",
            previous_version: "2.63.0",
            requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/azurerm" {
                version     = "2.64.0"
            DEP
          )
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/azurerm" {
                version     = "2.64.0"
            DEP
          )
        end
      end
    end

    describe "when updating provider with backend in configuration" do
      let(:project_name_base) { "provider_with_backend" }
      let(:file_name) { "providers" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "hashicorp/azurerm",
            version: "2.64.0",
            previous_version: "2.63.0",
            requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/azurerm"
              }
            }],
            previous_requirements: [{
              requirement: ">= 2.48.0",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/azurerm" {
                version     = "2.64.0"
            DEP
          )
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/hashicorp/azurerm" {
                version     = "2.64.0"
            DEP
          )
        end
      end
    end

    describe "when updating a provider with mixed case path" do
      let(:project_name_base) { "provider_with_mixed_case" }
      let(:file_name) { "providers" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Mongey/confluentcloud",
            version: "0.0.11",
            previous_version: "0.0.6",
            requirements: [{
              requirement: ">= 0.0.11, < 0.0.12",
              groups: [],
              file: file_name,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            previous_requirements: [{
              requirement: ">= 0.0.6, < 0.0.12",
              groups: [],
              file: file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/mongey/confluentcloud" {
                version     = "0.0.11"
            DEP
          )
        end
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/mongey/confluentcloud" {
                version     = "0.0.11"
            DEP
          )
        end
      end
    end

    describe "when updating a provider with multiple local path modules" do
      let(:project_name_base) { "provider_with_multiple_local_path_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "Mongey/confluentcloud",
            version: "0.0.10",
            previous_version: "0.0.6",
            requirements: [{
              requirement: "0.0.10",
              groups: [],
              file: "providers" + file_extension,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.10",
              groups: [],
              file: "loader/providers" + file_extension,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.10",
              groups: [],
              file: "loader/project/providers" + file_extension,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }],
            previous_requirements: [{
              requirement: "0.0.6",
              groups: [],
              file: "providers" + file_extension,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.6",
              groups: [],
              file: "loader/providers" + file_extension,
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "Mongey/confluentcloud"
              }
            }, {
              requirement: "0.0.6",
              groups: [],
              file: "loader/project/providers" + file_extension,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        it "updates the module version across all nested providers" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }
          provider_files = updated_files.select { |file| file.name.end_with?(file_extension) }

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
      context "with modules in json format" do
        let(:file_format) { "json" }
        it "updates the module version across all nested providers" do
          lockfile = updated_files.find { |file| file.name == ".terraform.lock.hcl" }
          provider_files = updated_files.select { |file| file.name.end_with?(file_extension) }

          expect(provider_files.count).to eq(3)
          provider_files.each do |file|
            file_json = JSON.parse(file.content)
            version = file_json["terraform"][0]["required_providers"][0]["confluentcloud"]["version"]
            expect(version).to eq("0.0.10")
          end

          expect(lockfile.content).to include(
            <<~DEP
              provider "registry.terraform.io/mongey/confluentcloud" {
                version     = "0.0.10"
            DEP
          )
        end
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
      let(:project_name_base) { "duplicate_child_modules" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "origin_label",
            version: "0.4.1",
            previous_version: "0.3.7",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "child_module_one/" + file_name,
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
              file: "child_module_one/" + file_name,
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

      context "with modules in hcl format" do
        let(:file_format) { "tf" }
        specify { expect(subject).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(subject.length).to eq(1) }
      end
      context "with modules in json format" do
        let(:file_format) { "json" }
        specify { expect(subject).to all(be_a(Dependabot::DependencyFile)) }
        specify { expect(subject.length).to eq(1) }
      end
    end
  end
end
