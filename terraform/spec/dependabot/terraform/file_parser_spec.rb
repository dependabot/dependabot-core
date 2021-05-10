# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/terraform/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Terraform::FileParser do
  it_behaves_like "a dependency file parser"

  subject(:parser) { described_class.new(dependency_files: files, source: source) }

  let(:files) { [] }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }

  describe "#parse" do
    subject { parser.parse }

    context "with an unparseable source" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "unparseable", "main.tf")
          )
        ]
      end

      it "raises an error" do
        expect { subject }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_path).to eq("/main.tf")
          expect(error.message).to match(/Failed to convert file: .* An argument or block definition is required here/)
        end
      end
    end

    context "with terraform 12 - no interpolaction" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "module", "main.tf")
          )
        ]
      end

      it "gets the right dependencies" do
      end
      its(:length) { is_expected.to eq(1) }
    end

    context "with valid registry sources" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "registry", "main.tf")
          )
        ]
      end

      specify { expect(subject.length).to eq(5) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency (default registry with version)" do
        dependency = subject[0]

        expect(dependency.name).to eq("hashicorp/consul/aws")
        expect(dependency.version).to eq("0.1.0")
        expect(dependency.requirements).to eq([{
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

      it "has the right details for the second dependency (default registry with no version)" do
        dependency = subject[1]

        expect(dependency.name).to eq("devops-workflow/members/github")
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
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

      it "has the right details for the third dependency (default registry with a sub-directory)" do
        dependency = subject[2]

        expect(dependency.name).to eq("mongodb/ecs-task-definition/aws")
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
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

      it "has the right details for the fourth dependency (default registry with version requirements)" do
        dependency = subject[3]

        expect(dependency.name).to eq("terraform-aws-modules/rds/aws")
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
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

      it "has the right details for the fifth dependency (private registry with version)" do
        dependency = subject[4]

        expect(dependency.name).to eq("example_corp/vpc/aws")
        expect(dependency.version).to eq("0.9.3")
        expect(dependency.requirements).to eq([{
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
    end

    context "with v0.11 git sources" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "git_tags_011", "main.tf")
          )
        ]
      end

      specify { expect(subject.length).to eq(6) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency (which uses git:: with a tag)" do
        dependency = subject.find { |x| x.name == "origin_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.3.7")
        expect(dependency.requirements).to match_array([{
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
        dependency = subject.find { |x| x.name == "logs" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.2.2")
        expect(dependency.requirements).to match_array([{
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
        dependency = subject.find { |x| x.name == "distribution_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
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
        dependency = subject.find { |x| x.name == "dns" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.2.5")
        expect(dependency.requirements).to eq([{
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
        dependency = subject.find { |x| x.name == "duplicate_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.3.7")
        expect(dependency.requirements).to eq([{
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
        dependency = subject.find { |x| x.name == "github_ssh_without_protocol" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.4.0")
        expect(dependency.requirements).to eq([{
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

    context "with v0.12+ git sources" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "git_tags_012", "main.tf")
          )
        ]
      end

      specify { expect(subject.length).to eq(6) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency (which uses git:: with a tag)" do
        dependency = subject.find { |x| x.name == "origin_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.3.7")
        expect(dependency.requirements).to match_array([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: "0.3.7"
          }
        }])
      end

      it "has the right details for the second dependency (which uses github.com with a tag)" do
        dependency = subject.find { |x| x.name == "logs" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.2.2")
        expect(dependency.requirements).to match_array([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-aws-s3-log-storage.git",
            branch: nil,
            ref: "0.2.2"
          }
        }])
      end

      it "has the right details for the third dependency (which uses bitbucket.org with no tag)" do
        dependency = subject.find { |x| x.name == "distribution_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
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
        dependency = subject.find { |x| x.name == "dns" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.2.5")
        expect(dependency.requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
            branch: nil,
            ref: "0.2.5"
          }
        }])
      end

      it "has the right details the fifth dependency)" do
        dependency = subject.find { |x| x.name == "duplicate_label" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.3.7")
        expect(dependency.requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: "0.3.7"
          }
        }])
      end

      it "has the right details for the sixth dependency (which uses git@github.com)" do
        dependency = subject.find { |x| x.name == "github_ssh_without_protocol" }
        expect(dependency).to_not be_nil
        expect(dependency.version).to eq("0.4.0")
        expect(dependency.requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
            ref: "0.4.0",
            branch: nil
          }
        }])
      end
    end

    context "with a terragrunt file" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "terragrunt.hcl",
            content: fixture("projects", "terragrunt", "terragrunt.hcl")
          )
        ]
      end

      specify { expect(subject.length).to eq(1) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the first dependency" do
        expect(subject[0].name).to eq("gruntwork-io/modules-example")
        expect(subject[0].version).to eq("0.0.2")
        expect(subject[0].requirements).to eq([{
          requirement: nil,
          groups: [],
          file: "terragrunt.hcl",
          source: {
            type: "git",
            url: "git@github.com:gruntwork-io/modules-example.git",
            branch: nil,
            ref: "v0.0.2"
          }
        }])
      end
    end

    context "with a provider block" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "main.tf",
            content: fixture("projects", "required_provider", "main.tf")
          )
        ]
      end

      it "has the right details" do
        dependency = subject.first

        expect(dependency.name).to eq("hashicorp/aws")
        expect(dependency.version).to eq("0.1.0")
      end
    end
  end
end
