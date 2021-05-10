# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/terraform/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Terraform::FileParser do
  it_behaves_like "a dependency file parser"

  subject(:parser) { described_class.new(dependency_files: files, source: source, options: {terraform_hcl2: PackageManagerHelper.use_terraform_hcl2?} ) }

  let(:files) { [] }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }

  describe "#parse" do
    subject { parser.parse }

    context "with an invalid registry source" do
      let(:files) { project_dependency_files("invalid_registry") }

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |boom|
          expect(boom.message).to eq("Invalid registry source specified: 'consul/aws'")
        end
      end
    end

    context "with an unparseable source" do
      let(:files) { project_dependency_files("unparseable") }

      it "raises an error" do
        expect { subject }.to raise_error(Dependabot::DependencyFileNotParseable) do |boom|
          expect(boom.file_path).to eq("/main.tf")
          expect(boom.message).to eq("unable to parse HCL: object expected closing RBRACE got: EOF")
        end
      end
    end

    context "with valid registry sources" do
      let(:files) { project_dependency_files("registry") }

      specify { expect(subject.length).to eq(5) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency (default registry with version)" do
        expect(subject[0].name).to eq("hashicorp/consul/aws")
        expect(subject[0].version).to eq("0.1.0")
        expect(subject[0].requirements).to eq([{
          requirement: "0.1.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/consul/aws"
          }
        }])
      end

      it "has the right details for the second dependency (private registry with version)" do
        expect(subject[1].name).to eq("example_corp/vpc/aws")
        expect(subject[1].version).to eq("0.9.3")
        expect(subject[1].requirements).to eq([{
          requirement: "0.9.3",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "app.terraform.io",
            module_identifier: "example_corp/vpc/aws"
          }
        }])
      end

      it "has the right details for the third dependency (default registry with version req)" do
        expect(subject[2].name).to eq("terraform-aws-modules/rds/aws")
        expect(subject[2].version).to be_nil
        expect(subject[2].requirements).to eq([{
          requirement: "~> 1.0.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "terraform-aws-modules/rds/aws"
          }
        }])
      end

      it "has the right details for the fourth dependency (default registry with no version)" do
        expect(subject[3].name).to eq("devops-workflow/members/github")
        expect(subject[3].version).to be_nil
        expect(subject[3].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "devops-workflow/members/github"
          }
        }])
      end

      it "has the right details for the fifth dependency (default registry with a sub-directory)" do
        expect(subject[4].name).to eq("mongodb/ecs-task-definition/aws")
        expect(subject[4].version).to be_nil
        expect(subject[4].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: "mongodb/ecs-task-definition/aws"
          }
        }])
      end
    end

    context "with git sources" do
      let(:files) { project_dependency_files("git_tags") }

      specify { expect(subject.length).to eq(6) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency (which uses git:: with a tag)" do
        expect(subject[0].name).to eq("origin_label")
        expect(subject[0].version).to eq("0.3.7")
        expect(subject[0].requirements).to match_array([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: "tags/0.3.7"
          }
        }])
      end

      it "has the right details for the second dependency (which uses github.com with a tag)" do
        expect(subject[1].name).to eq("logs")
        expect(subject[1].version).to eq("0.2.2")
        expect(subject[1].requirements).to match_array([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-log-storage.git",
            branch: nil,
            ref: "tags/0.2.2"
          }
        }])
      end

      it "has the right details for the third dependency (which uses bitbucket.org with no tag)" do
        expect(subject[2].name).to eq("distribution_label")
        expect(subject[2].version).to be_nil
        expect(subject[2].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://bitbucket.org/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: nil
          }
        }])
      end

      it "has the right details the fourth dependency (which has a subdirectory and a tag)" do
        expect(subject[3].name).to eq("dns")
        expect(subject[3].version).to eq("0.2.5")
        expect(subject[3].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-aws-route53-al.git",
            branch: nil,
            ref: "tags/0.2.5"
          }
        }])
      end

      it "has the right details the fifth dependency)" do
        expect(subject[4].name).to eq("duplicate_label")
        expect(subject[4].version).to eq("0.3.7")
        expect(subject[4].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: "tags/0.3.7"
          }
        }])
      end

     it "has the right details for the sixth dependency (which uses git@github.com)" do
        expect(subject[5].name).to eq("github_ssh_without_protocol")
        expect(subject[5].version).to eq("0.4.0")
        expect(subject[5].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
            ref: "tags/0.4.0",
            branch: nil
          }
        }])
      end
    end

    context "with a terragrunt file" do
      let(:files) { project_dependency_files("terragrunt") }

      specify { expect(subject.length).to eq(1) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency" do
        expect(subject[0].name).to eq("gruntwork-io/modules-example")
        expect(subject[0].version).to eq("0.0.2")
        expect(subject[0].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tfvars",
          source: {
            type: "git",
            url: "git@github.com:gruntwork-io/modules-example.git",
            branch: nil,
            ref: "v0.0.2"
          }
        }])
      end
    end

    context "with the hcl2 option", :hcl2_only do
      let(:files) { project_dependency_files("hcl2") }
      it "has the right source for the dependency" do
        expect(subject[0].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
            branch: nil,
            ref: "0.4.0"
          }
        }])
      end
    end

    context "with the hcl1_only option", :hcl1_only do 
      
    end

  end
end
