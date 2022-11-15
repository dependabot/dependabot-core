# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/terraform/file_parser"
require "dependabot/terraform/version"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Terraform::FileParser do
  it_behaves_like "a dependency file parser"

  subject(:parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end

  let(:files) { [] }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }

  describe "#parse" do
    subject(:dependencies) { parser.parse }

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
          expect(boom.message).to eq(
            "Failed to convert file: parse config: [:18,1-1: Argument or block definition required; " \
            "An argument or block definition is required here.]"
          )
        end
      end
    end

    context "with valid registry sources" do
      let(:files) { project_dependency_files("registry") }

      specify { expect(subject.length).to eq(5) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the dependency (default registry with version)" do
        expect(subject[2].name).to eq("hashicorp/consul/aws")
        expect(subject[2].version).to eq("0.1.0")
        expect(subject[2].requirements).to eq([{
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

      it "has the right details for the dependency (default registry with version req)" do
        expect(subject[4].name).to eq("terraform-aws-modules/rds/aws")
        expect(subject[4].version).to be_nil
        expect(subject[4].requirements).to eq([{
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

      it "has the right details for the dependency (default registry with no version)" do
        expect(subject[0].name).to eq("devops-workflow/members/github")
        expect(subject[0].version).to be_nil
        expect(subject[0].requirements).to eq([{
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

      it "has the right details for the dependency (default registry with a sub-directory)" do
        expect(subject[3].name).to eq("mongodb/ecs-task-definition/aws")
        expect(subject[3].version).to be_nil
        expect(subject[3].requirements).to eq([{
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

    context "with a private registry" do
      let(:files) { project_dependency_files("private_registry") }

      it "parses the dependency correctly" do
        expect(subject.length).to eq(1)
        expect(subject[0].name).to eq("namespace/name")
        expect(subject[0].version).to eq("0.1.0")
        expect(subject[0].requirements).to eq([{
          requirement: "0.1.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.example.org",
            module_identifier: "namespace/name"
          }
        }])
      end
    end

    context "with a private registry using a pessimistic version constraint" do
      let(:files) { project_dependency_files("private_registry_pessimistic_constraint") }

      it "parses the dependency correctly" do
        expect(subject.length).to eq(1)
        expect(subject[0].name).to eq("namespace/name")
        expect(subject[0].version).to be_nil
        expect(subject[0].requirements).to eq([{
          requirement: "~> 0.1",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.example.org",
            module_identifier: "namespace/name"
          }
        }])
      end
    end

    context "with a pessimistic constraint and a lockfile" do
      let(:files) { project_dependency_files("pessimistic_constraint_lock_file") }

      it "parses the lockfile" do
        expect(subject.length).to eq(1)
      end

      it "parses the dependency correctly" do
        expect(subject[0].name).to eq("hashicorp/http")
        expect(subject[0].version).to eq("2.1.0")
        expect(subject[0].requirements).to eq([{
          requirement: "~> 2.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/http"
          }
        }])
      end
    end

    context "with git sources" do
      let(:version_class) { Dependabot::Terraform::Version }
      let(:files) { project_dependency_files("git_tags_011") }
      specify { expect(subject.length).to eq(6) }
      specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the dependency (which uses git:: with a tag)" do
        expect(subject[5].name).to eq("origin_label::github::cloudposse/terraform-null-label::tags/0.3.7")
        expect(subject[5].version).to eq("0.3.7")
        expect(subject[5].requirements).to match_array([{
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

      it "has the right details for the dependency (which uses github.com with a tag)" do
        expect(subject[4].name).to eq("logs::github::cloudposse/terraform-log-storage::tags/0.2.2")
        expect(subject[4].version).to eq("0.2.2")
        expect(subject[4].requirements).to match_array([{
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

      it "has the right details for the dependency (which uses bitbucket.org with no tag)" do
        expect(subject[0].name).to eq("distribution_label::bitbucket::cloudposse/terraform-null-label")
        expect(subject[0].version).to be_nil
        expect(subject[0].requirements).to eq([{
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

      it "has the right details for the dependency (which has a subdirectory and a tag)" do
        expect(subject[1].name).to eq("dns::github::cloudposse/terraform-aws-route53-al::tags/0.2.5")
        expect(subject[1].version).to eq("0.2.5")
        expect(subject[1].requirements).to eq([{
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

      it "has the right details for the dependency" do
        expect(subject[2].name).to eq("duplicate_label::github::cloudposse/terraform-null-label::tags/0.3.7")
        expect(subject[2].version).to eq("0.3.7")
        expect(subject[2].requirements).to eq([{
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

      it "has the right details for the dependency (which uses git@github.com)" do
        expect(subject[3].name).to \
          eq("github_ssh_without_protocol::github::cloudposse/terraform-aws-jenkins::tags/0.4.0")
        expect(subject[3].version).to eq("0.4.0")
        expect(subject[3].requirements).to eq([{
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

    context "deprecated terraform provider syntax" do
      let(:files) { project_dependency_files("deprecated_provider") }

      it "raises a helpful error message" do
        expect { subject }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.message).to eq(
            "This terraform provider syntax is now deprecated.\n" \
            "See https://www.terraform.io/docs/language/providers/requirements.html " \
            "for the new Terraform v0.13+ provider syntax."
          )
        end
      end
    end

    context "hcl2 files" do
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
            ref: "0.4.1"
          }
        }])
      end

      context "with git sources" do
        let(:files) { project_dependency_files("git_tags_012") }

        specify { expect(subject.length).to eq(6) }
        specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the first dependency (which uses git:: with a tag)" do
          dependency = subject.find do |x|
            x.name == "origin_label::github::cloudposse/terraform-null-label::tags/0.3.7"
          end
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
          dependency = subject.find do |x|
            x.name == "logs::github::cloudposse/terraform-aws-s3-log-storage::tags/0.2.2"
          end
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
              ref: "tags/0.2.2"
            }
          }])
        end

        it "has the right details for the third dependency (which uses bitbucket.org with no tag)" do
          dependency = subject.find { |x| x.name == "distribution_label::bitbucket::cloudposse/terraform-null-label" }
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
          dependency = subject.find do |x|
            x.name == "dns::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
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
              ref: "tags/0.2.5"
            }
          }])
        end

        it "has the right details the fifth dependency)" do
          dependency = subject.find do |x|
            x.name == "duplicate_label::github::cloudposse/terraform-null-label::tags/0.3.7"
          end
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
          dependency = subject.find do |x|
            x.name == "github_ssh_without_protocol::github::cloudposse/terraform-aws-jenkins::tags/0.4.0"
          end
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

      before do
        stub_request(:get, "https://unknown-git-repo-example.com/status").to_return(
          status: 200,
          body: "Not GHES",
          headers: {}
        )
      end

      context "with relative path" do
        let(:files) { project_dependency_files("git_tags_013") }
        specify { expect(subject.length).to eq(8) }
        specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the child_module_one child_label git dependency (uses git@github.com)" do
          dependency = subject.find { |x| x.name == "child::github::cloudposse/terraform-aws-jenkins::tags/0.4.0" }
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.4.0")
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "child_module_one/main.tf",
            source: {
              type: "git",
              url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
              branch: nil,
              ref: "tags/0.4.0"
            }
          }])
        end

        it "has the right details for the child_module_two child_label git dependency (uses github.com with a tag)" do
          dependency = subject.find do |x|
            x.name == "child::github::cloudposse/terraform-aws-s3-log-storage::tags/0.2.2"
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.2.2")
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "child_module_two/main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-s3-log-storage.git",
              branch: nil,
              ref: "tags/0.2.2"
            }
          }])
        end

        it "has the right details for the child_module_one distribution_label duplicate git repo different provider" do
          dependency = subject.find { |x| x.name == "distribution_label::github::cloudposse/terraform-null-label" }
          expect(dependency).to_not be_nil
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "child_module_one/main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: nil
            }
          }])
        end

        it "has the right details for the child_module_two distribution_label duplicate git repo different provider" do
          dependency = subject.find { |x| x.name == "distribution_label::bitbucket::cloudposse/terraform-null-label" }
          expect(dependency).to_not be_nil
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "child_module_two/main.tf",
            source: {
              type: "git",
              url: "https://bitbucket.org/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: nil
            }
          }])
        end

        it "has the right details for the dns_dup with duplicate git repo" do
          dependency = subject.find do |x|
            x.name == "dns_dup::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.2.5")
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
              branch: nil,
              ref: "tags/0.2.5"
            }
          }])
        end

        it "has the right details for the dns with child module duplicate and duplicate git repo" do
          dependency = subject.find do |x|
            x.name == "dns::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.2.5")
          expect(dependency.requirements).to match_array([
            {
              requirement: nil,
              groups: [],
              file: "child_module_two/main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
                branch: nil,
                ref: "tags/0.2.5"
              }
            },
            {
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "git",
                url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
                branch: nil,
                ref: "tags/0.2.5"
              }
            }
          ])
        end

        it "has the right details for the codecommit git repo" do
          dependency = subject.find do |x|
            x.name == "codecommit_repo::codecommit::test-repo::0.10.0"
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.10.0")
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/test-repo",
              branch: nil,
              ref: "0.10.0"
            }
          }])
        end

        it "has the right details for the unknown git repo example" do
          dependency = subject.find do |x|
            x.name.include? "unknown_repo::git_provider::repo_name/git_repo("
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to match_array([{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://unknown-git-repo-example.com/reponame/test",
              branch: nil,
              ref: "1.0.0"
            }
          }])
        end
      end

      context "with git@xxx.yy sources" do
        let(:files) { project_dependency_files("git_protocol") }

        specify { expect(subject.length).to eq(1) }
        specify { expect(subject).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the first dependency (which uses git@gitlab.com)" do
          dependency = subject.find do |x|
            x.name == "gitlab_ssh_without_protocol::gitlab::cloudposse/terraform-aws-jenkins::tags/0.4.0"
          end
          expect(dependency).to_not be_nil
          expect(dependency.version).to eq("0.4.0")
          expect(dependency.requirements).to eq([{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "git@gitlab.com:cloudposse/terraform-aws-jenkins.git",
              ref: "tags/0.4.0",
              branch: nil
            }
          }])
        end
      end

      context "with registry sources" do
        let(:files) { project_dependency_files("registry_012") }

        its(:length) { is_expected.to eq(5) }

        describe "default registry with version" do
          subject(:dependency) { dependencies.find { |d| d.name == "hashicorp/consul/aws" } }
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

        describe "default registry with no version" do
          subject(:dependency) { dependencies.find { |d| d.name == "devops-workflow/members/github" } }
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

        describe "the third dependency (default registry with a sub-directory)" do
          subject(:dependency) { dependencies.find { |d| d.name == "mongodb/ecs-task-definition/aws" } }
          let(:expected_requirements) do
            [{
              requirement: nil,
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "mongodb/ecs-task-definition/aws"
              }
            }]
          end

          it "has the right details" do
            expect(dependency).to be_a(Dependabot::Dependency)
            expect(dependency.name).to eq("mongodb/ecs-task-definition/aws")
            expect(dependency.version).to be_nil
            expect(dependency.requirements).to eq(expected_requirements)
          end
        end

        describe "the fourth dependency (default registry with version req)" do
          subject(:dependency) { dependencies.find { |d| d.name == "terraform-aws-modules/rds/aws" } }
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

        describe "the fifth dependency (private registry with version)" do
          subject(:dependency) { dependencies.find { |d| d.name == "example_corp/vpc/aws" } }
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
      end

      context "with terragrunt files" do
        let(:files) { project_dependency_files("terragrunt_hcl") }

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
    end

    context "terraform.lock.hcl files" do
      let(:files) { project_dependency_files("terraform_lock_only") }

      it "does not attempt to parse the lockfile" do
        expect { dependencies.length }.to raise_error(RuntimeError) do |error|
          expect(error.message).to eq("No Terraform configuration file!")
        end
      end
    end

    context "with a required provider" do
      let(:files) { project_dependency_files("registry_provider") }

      it "has the right details" do
        dependency = dependencies.find { |d| d.name == "hashicorp/aws" }

        expect(dependency.version).to eq("3.37.0")
      end

      it "handles version ranges correctly" do
        dependency = dependencies.find { |d| d.name == "hashicorp/http" }

        expect(dependency.version).to be_nil
        expect(dependency.requirements).to eq([{
          requirement: "~> 2.0",
          groups: [],
          file: "main.tf",
          source: {
            type: "provider",
            registry_hostname: "registry.terraform.io",
            module_identifier: "hashicorp/http"
          }
        }])
      end
    end

    context "with a required provider block with multiple versions" do
      let(:files) { project_dependency_files("registry_provider_compound_local_name") }

      it "has the right details" do
        hashicorp = dependencies.find { |d| d.name == "hashicorp/http" }
        mycorp = dependencies.find { |d| d.name == "mycorp/http" }

        expect(hashicorp.version).to eq("2.0")
        expect(mycorp.version).to eq("1.0")
      end
    end

    context "with a required provider that does not specify a source" do
      let(:files) { project_dependency_files("provider_implicit_source") }

      it "has the right details" do
        dependency = dependencies.find { |d| d.name == "oci" }

        expect(dependency.version).to eq("3.27")
        expect(dependency.requirements.first[:source][:module_identifier]).to eq("hashicorp/oci")
      end
    end

    context "with a toplevel provider" do
      let(:files) { project_dependency_files("provider") }

      it "does not find the details" do
        # This feature is deprecated as documented here:
        # https://www.terraform.io/docs/language/providers/configuration.html#version-an-older-way-to-manage-provider-versions
        # So dependabot does not support it. This test is here for
        # documentatio-sake.
        expect(dependencies.count).to eq(0)
      end
    end

    context "with a provider that doesn't have a namespace provider" do
      let(:files) { project_dependency_files("provider_no_namespace") }

      it "has the right details" do
        dependency = dependencies.find { |d| d.name == "hashicorp/random" }

        expect(dependency.version).to eq("2.2.1")
        expect(dependency.requirements.first[:source][:module_identifier]).to eq("hashicorp/random")
      end
    end

    context "with a private module with directory suffix" do
      let(:files) { project_dependency_files("private_module_with_dir_suffix") }
      its(:length) { is_expected.to eq(1) }

      describe "default registry with version" do
        subject(:dependency) { dependencies.find { |d| d.name == "org/name/provider" } }
        let(:expected_requirements) do
          [{
            requirement: "1.2.3",
            groups: [],
            file: "main.tf",
            source: {
              type: "registry",
              registry_hostname: "registry.example.com",
              module_identifier: "org/name/provider"
            }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org/name/provider")
          expect(dependency.version).to eq("1.2.3")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a private module proxy that can't be reached", vcr: true do
      let(:files) { project_dependency_files("private_module_proxy") }

      it "raises an error" do
        expect { subject }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |boom|
          expect(boom.source).to eq("artifactory.dependabot.com")
        end
      end
    end
  end
end
