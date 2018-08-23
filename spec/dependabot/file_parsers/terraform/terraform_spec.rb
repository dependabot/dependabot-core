# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/file_parsers/terraform/terraform"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Terraform::Terraform do
  it_behaves_like "a dependency file parser"

  let(:files) { [terraform_file] }
  let(:terraform_file) do
    Dependabot::DependencyFile.new(name: "main.tf", content: terraform_body)
  end
  let(:terraform_body) do
    fixture("terraform", "config_files", terraform_fixture_name)
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

      its(:length) { is_expected.to eq(4) }

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
    end
  end
end
