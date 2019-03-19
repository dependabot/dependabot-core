# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/terraform/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Terraform::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [terraform_file] }
  let(:terraform_file) do
    Dependabot::DependencyFile.new(name: "main.tf", content: terraform_body)
  end
  let(:terraform_body) do
    fixture("config_files", terraform_fixture_name)
  end
  let(:terraform_fixture_name) { "git_tags.tf" }
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

    context "with registry sources" do
      let(:terraform_fixture_name) { "registry.tf" }

      its(:length) { is_expected.to eq(4) }

      context "that are invalid" do
        let(:terraform_fixture_name) { "invalid_registry.tf" }

        it "raises a helpful error" do
          expect { parser.parse }.
            to raise_error(Dependabot::DependencyFileNotEvaluatable) do |err|
              expect(err.message).
                to eq("Invalid registry source specified: 'consul/aws'")
            end
        end
      end

      describe "the first dependency (default registry with version)" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "0.1.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: "registry.terraform.io",
              module_identifier: "hashicorp/consul/aws"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("hashicorp/consul/aws")
          expect(dependency.version).to eq("0.1.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (private registry with version)" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: "0.9.3",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: "app.terraform.io",
              module_identifier: "example_corp/vpc/aws"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("example_corp/vpc/aws")
          expect(dependency.version).to eq("0.9.3")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the third dependency (default registry with version req)" do
        subject(:dependency) { dependencies[2] }
        let(:expected_requirements) do
          [{
            requirement: "~> 1.0.0",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: "registry.terraform.io",
              module_identifier: "terraform-aws-modules/rds/aws"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("terraform-aws-modules/rds/aws")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the fourth dependency (default registry with no version)" do
        subject(:dependency) { dependencies[3] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: "registry.terraform.io",
              module_identifier: "devops-workflow/members/github"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("devops-workflow/members/github")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with git sources" do
      let(:terraform_fixture_name) { "git_tags.tf" }

      its(:length) { is_expected.to eq(6) }

      describe "the first dependency (which uses git:: with a tag)" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: "tags/0.3.7"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("origin_label")
          expect(dependency.version).to eq("0.3.7")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency (which uses github.com with a tag)" do
        subject(:dependency) { dependencies[1] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-log-storage.git",
              branch: nil,
              ref: "tags/0.2.2"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("logs")
          expect(dependency.version).to eq("0.2.2")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the third dependency (which uses bitbucket.org with no tag)" do
        subject(:dependency) { dependencies[2] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://bitbucket.org/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: nil
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("distribution_label")
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the fourth dependency (which has a subdirectory and a tag)" do
        subject(:dependency) { dependencies[3] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-route53-al.git",
              branch: nil,
              ref: "tags/0.2.5"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("dns")
          expect(dependency.version).to eq("0.2.5")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the sixth dependency (which uses git@github.com)" do
        subject(:dependency) { dependencies[5] }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
              ref: "tags/0.4.0",
              branch: nil
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("github_ssh_without_protocol")
          expect(dependency.version).to eq("0.4.0")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a terragrunt file" do
      let(:files) { [terragrunt_file] }
      let(:terragrunt_file) do
        Dependabot::DependencyFile.new(
          name: "main.tfvars",
          content: terragrunt_body
        )
      end
      let(:terragrunt_body) do
        fixture("config_files", terragrunt_fixture_name)
      end
      let(:terragrunt_fixture_name) { "terragrunt.tfvars" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            file: "main.tfvars",
            source: {
              type: "git",
              url: "git@github.com:gruntwork-io/modules-example.git",
              branch: nil,
              ref: "v0.0.2"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("gruntwork-io/modules-example")
          expect(dependency.version).to eq("0.0.2")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end
  end
end
