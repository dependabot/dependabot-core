# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/terraform/file_parser"
require "dependabot/terraform/version"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Terraform::FileParser do
  subject(:parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end

  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }
  let(:files) { project_dependency_files("registry") }
  let(:file_parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }
  let(:files) { [] }

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    let(:files) { [] }
    let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }

    context "with an invalid registry source" do
      let(:files) { project_dependency_files("invalid_registry") }

      it "raises a helpful error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |boom|
          expect(boom.message).to eq("Invalid registry source specified: 'consul/aws'")
        end
      end
    end

    context "with an unparseable source" do
      let(:files) { project_dependency_files("unparseable") }

      it "raises an error" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable) do |boom|
          expect(boom.message).to eq(
            "Failed to convert file: parse config: [STDIN:1,17-18: Unclosed configuration block; " \
            "There is no closing brace for this block before the end of the file. " \
            "This may be caused by incorrect brace nesting elsewhere in this file.]"
          )
        end
      end
    end

    context "with valid registry sources" do
      let(:files) { project_dependency_files("registry") }

      specify { expect(dependencies.length).to eq(5) }
      specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the dependency (default registry with version)" do
        expect(dependencies[2].name).to eq("hashicorp/consul/aws")
        expect(dependencies[2].version).to eq("0.1.0")
        expect(dependencies[2].requirements).to eq([{
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
        expect(dependencies[1].name).to eq("example_corp/vpc/aws")
        expect(dependencies[1].version).to eq("0.9.3")
        expect(dependencies[1].requirements).to eq([{
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
        expect(dependencies[4].name).to eq("terraform-aws-modules/rds/aws")
        expect(dependencies[4].version).to be_nil
        expect(dependencies[4].requirements).to eq([{
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
        expect(dependencies[0].name).to eq("devops-workflow/members/github")
        expect(dependencies[0].version).to be_nil
        expect(dependencies[0].requirements).to eq([{
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
        expect(dependencies[3].name).to eq("mongodb/ecs-task-definition/aws")
        expect(dependencies[3].version).to be_nil
        expect(dependencies[3].requirements).to eq([{
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
        expect(dependencies.length).to eq(1)
        expect(dependencies[0].name).to eq("namespace/name")
        expect(dependencies[0].version).to eq("0.1.0")
        expect(dependencies[0].requirements).to eq([{
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
        expect(dependencies.length).to eq(1)
        expect(dependencies[0].name).to eq("namespace/name")
        expect(dependencies[0].version).to be_nil
        expect(dependencies[0].requirements).to eq([{
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
      let(:files) { project_dependency_files("pessimistic_constraint_lockfile") }

      it "parses the lockfile" do
        expect(dependencies.length).to eq(1)
      end

      it "parses the dependency correctly" do
        expect(dependencies[0].name).to eq("hashicorp/http")
        expect(dependencies[0].version).to eq("2.1.0")
        expect(dependencies[0].requirements).to eq([{
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

      specify { expect(dependencies.length).to eq(6) }
      specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

      it "has the right details for the dependency (which uses git:: with a tag)" do
        expect(dependencies[5].name).to eq("origin_label::github::cloudposse/terraform-null-label::tags/0.3.7")
        expect(dependencies[5].version).to eq("0.3.7")
        expect(dependencies[5].requirements).to contain_exactly({
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-null-label.git",
            branch: nil,
            ref: "tags/0.3.7"
          }
        })
      end

      it "has the right details for the dependency (which uses github.com with a tag)" do
        expect(dependencies[4].name).to eq("logs::github::cloudposse/terraform-log-storage::tags/0.2.2")
        expect(dependencies[4].version).to eq("0.2.2")
        expect(dependencies[4].requirements).to contain_exactly({
          requirement: nil,
          groups: [],
          file: "main.tf",
          source: {
            type: "git",
            url: "https://github.com/cloudposse/terraform-log-storage.git",
            branch: nil,
            ref: "tags/0.2.2"
          }
        })
      end

      it "has the right details for the dependency (which uses bitbucket.org with no tag)" do
        expect(dependencies[0].name).to eq("distribution_label::bitbucket::cloudposse/terraform-null-label")
        expect(dependencies[0].version).to be_nil
        expect(dependencies[0].requirements).to eq([{
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
        expect(dependencies[1].name).to eq("dns::github::cloudposse/terraform-aws-route53-al::tags/0.2.5")
        expect(dependencies[1].version).to eq("0.2.5")
        expect(dependencies[1].requirements).to eq([{
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
        expect(dependencies[2].name).to eq("duplicate_label::github::cloudposse/terraform-null-label::tags/0.3.7")
        expect(dependencies[2].version).to eq("0.3.7")
        expect(dependencies[2].requirements).to eq([{
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
        expect(dependencies[3].name).to eq(
          "github_ssh_without_protocol::github::cloudposse/terraform-aws-jenkins::tags/0.4.0"
        )
        expect(dependencies[3].version).to eq("0.4.0")
        expect(dependencies[3].requirements).to eq([{
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

    context "when dealing with a deprecated terraform provider syntax" do
      let(:files) { project_dependency_files("deprecated_provider") }

      it "raises a helpful error message" do
        expect { dependencies }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.message).to eq(
            "This terraform provider syntax is now deprecated.\n" \
            "See https://www.terraform.io/docs/language/providers/requirements.html " \
            "for the new Terraform v0.13+ provider syntax."
          )
        end
      end
    end

    context "when dealing with hcl2 files" do
      let(:files) { project_dependency_files("hcl2") }

      before do
        stub_request(:get, "https://unknown-git-repo-example.com/status").to_return(
          status: 200,
          body: "Not GHES",
          headers: {}
        )
      end

      it "has the right source for the dependency" do
        expect(dependencies[0].requirements).to eq([{
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

        specify { expect(dependencies.length).to eq(6) }
        specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the first dependency (which uses git:: with a tag)" do
          dependency = dependencies.find do |x|
            x.name == "origin_label::github::cloudposse/terraform-null-label::tags/0.3.7"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.3.7")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: "tags/0.3.7"
            }
          })
        end

        it "has the right details for the second dependency (which uses github.com with a tag)" do
          dependency = dependencies.find do |x|
            x.name == "logs::github::cloudposse/terraform-aws-s3-log-storage::tags/0.2.2"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.2.2")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-s3-log-storage.git",
              branch: nil,
              ref: "tags/0.2.2"
            }
          })
        end

        it "has the right details for the third dependency (which uses bitbucket.org with no tag)" do
          dependency = dependencies.find do |x|
            x.name == "distribution_label::bitbucket::cloudposse/terraform-null-label"
          end
          expect(dependency).not_to be_nil
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
          dependency = dependencies.find do |x|
            x.name == "dns::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
          expect(dependency).not_to be_nil
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
          dependency = dependencies.find do |x|
            x.name == "duplicate_label::github::cloudposse/terraform-null-label::tags/0.3.7"
          end
          expect(dependency).not_to be_nil
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
          dependency = dependencies.find do |x|
            x.name == "github_ssh_without_protocol::github::cloudposse/terraform-aws-jenkins::tags/0.4.0"
          end
          expect(dependency).not_to be_nil
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

      context "with relative path" do
        let(:files) { project_dependency_files("git_tags_013") }

        specify { expect(dependencies.length).to eq(8) }
        specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the child_module_one child_label git dependency (uses git@github.com)" do
          dependency = dependencies.find { |x| x.name == "child::github::cloudposse/terraform-aws-jenkins::tags/0.4.0" }
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.4.0")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "child_module_one/main.tf",
            source: {
              type: "git",
              url: "git@github.com:cloudposse/terraform-aws-jenkins.git",
              branch: nil,
              ref: "tags/0.4.0"
            }
          })
        end

        it "has the right details for the child_module_two child_label git dependency (uses github.com with a tag)" do
          dependency = dependencies.find do |x|
            x.name == "child::github::cloudposse/terraform-aws-s3-log-storage::tags/0.2.2"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.2.2")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "child_module_two/main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-s3-log-storage.git",
              branch: nil,
              ref: "tags/0.2.2"
            }
          })
        end

        it "has the right details for the child_module_one distribution_label duplicate git repo different provider" do
          dependency = dependencies.find { |x| x.name == "distribution_label::github::cloudposse/terraform-null-label" }
          expect(dependency).not_to be_nil
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "child_module_one/main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: nil
            }
          })
        end

        it "has the right details for the child_module_two distribution_label duplicate git repo different provider" do
          dependency = dependencies.find do |x|
            x.name == "distribution_label::bitbucket::cloudposse/terraform-null-label"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to be_nil
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "child_module_two/main.tf",
            source: {
              type: "git",
              url: "https://bitbucket.org/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: nil
            }
          })
        end

        it "has the right details for the dns_dup with duplicate git repo" do
          dependency = dependencies.find do |x|
            x.name == "dns_dup::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.2.5")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
              branch: nil,
              ref: "tags/0.2.5"
            }
          })
        end

        it "has the right details for the dns with child module duplicate and duplicate git repo" do
          dependency = dependencies.find do |x|
            x.name == "dns::github::cloudposse/terraform-aws-route53-cluster-zone::tags/0.2.5"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.2.5")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "child_module_two/main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
              branch: nil,
              ref: "tags/0.2.5"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-aws-route53-cluster-zone.git",
              branch: nil,
              ref: "tags/0.2.5"
            }
          })
        end

        it "has the right details for the codecommit git repo" do
          dependency = dependencies.find do |x|
            x.name == "codecommit_repo::codecommit::test-repo::0.10.0"
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("0.10.0")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/test-repo",
              branch: nil,
              ref: "0.10.0"
            }
          })
        end

        it "has the right details for the unknown git repo example" do
          dependency = dependencies.find do |x|
            x.name.include? "unknown_repo::git_provider::repo_name/git_repo("
          end
          expect(dependency).not_to be_nil
          expect(dependency.version).to eq("1.0.0")
          expect(dependency.requirements).to contain_exactly({
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://unknown-git-repo-example.com/reponame/test",
              branch: nil,
              ref: "1.0.0"
            }
          })
        end
      end

      context "with git@xxx.yy sources" do
        let(:files) { project_dependency_files("git_protocol") }

        specify { expect(dependencies.length).to eq(1) }
        specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the first dependency (which uses git@gitlab.com)" do
          dependency = dependencies.find do |x|
            x.name == "gitlab_ssh_without_protocol::gitlab::cloudposse/terraform-aws-jenkins::tags/0.4.0"
          end
          expect(dependency).not_to be_nil
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

        specify { expect(dependencies.length).to eq(1) }
        specify { expect(dependencies).to all(be_a(Dependabot::Dependency)) }

        it "has the right details for the first dependency" do
          expect(dependencies[0].name).to eq("gruntwork-io/modules-example")
          expect(dependencies[0].version).to eq("0.0.2")
          expect(dependencies[0].requirements).to eq([{
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

    context "when dealing with terraform.lock.hcl files" do
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

    context "when the overridden module does not include source" do
      let(:files) { project_dependency_files("child_module_with_no_source") }

      it "has the module with no source" do
        module_dependency = dependencies.find { |d| d.name == "babbel/cloudfront-bucket/aws" }

        expect(module_dependency).not_to be_nil
        expect(module_dependency.version).to eq("2.2.0")
        expect(module_dependency.requirements.first[:source][:module_identifier]).to eq("babbel/cloudfront-bucket/aws")
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

    context "with a private module proxy that can't be reached", :vcr do
      before do
        artifactory_repo_url = "http://artifactory.dependabot.com/artifactory/tf-modules/azurerm"

        stub_request(:get, "#{artifactory_repo_url}/terraform-azurerm-nsg-rules.v1.1.0.tar.gz?terraform-get=1")
          .and_return(status: 401)
      end

      let(:files) { project_dependency_files("private_module_proxy") }

      it "raises an error" do
        expect { dependencies }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |boom|
          expect(boom.source).to eq("artifactory.dependabot.com")
        end
      end
    end
  end

  describe "#source_type" do
    subject(:source_type) { file_parser.send(:source_type, source_string) }

    let(:file_parser) { described_class.new(dependency_files: files, source: source) }

    let(:files) { project_dependency_files("registry") }
    let(:source) { Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: "/") }

    context "when the source type is known" do
      let(:source_string) { "github.com/org/repo" }

      it "returns the correct source type" do
        expect(source_type).to eq(:github)
      end
    end

    context "when the source type is a registry" do
      let(:source_string) { "registry.terraform.io/hashicorp/aws" }

      it "returns the correct source type" do
        expect(source_type).to eq(:registry)
      end
    end

    context "when the source type is an HTTP archive" do
      let(:source_string) { "https://example.com/archive.zip?ref=v1.0.0" }

      it "returns the correct source type" do
        expect(source_type).to eq(:http_archive)
      end
    end

    context "when the source type is an interpolation" do
      let(:source_string) { "${var.source}" }

      it "returns the correct source type" do
        expect(source_type).to eq(:interpolation)
      end
    end

    context "when the source type is an interpolation at the end" do
      let(:source_string) { "git::https://github.com/username/repo.git//path/to/${var.module_name}" }

      it "returns the correct source type" do
        expect(source_type).to eq(:interpolation)
      end
    end

    context "when the source type is an interpolation at the start" do
      let(:source_string) { "${var.repo_url}/username/repo.git" }

      it "returns the correct source type" do
        expect(source_type).to eq(:interpolation)
      end
    end

    context "when the source type is an interpolation type with multiple" do
      let(:source_string) { "git::https://github.com/${var.username}/${var.repo}//path/to/${var.module_name}" }

      it "returns the correct source type" do
        expect(source_type).to eq(:interpolation)
      end
    end

    context "when the source type is a compound interpolation" do
      let(:source_string) { "test/${var.map[${var.key}']" }

      it "returns the correct source type" do
        expect(source_type).to eq(:interpolation)
      end
    end

    context "when the source type is unknown" do
      let(:source_string) { "unknown_source" }

      it "returns the correct source type" do
        expect(source_type).to eq(:registry)
      end
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    let(:files) { project_dependency_files("registry") }

    it "has the correct name" do
      expect(ecosystem.name).to eq "terraform"
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager" do
        expect(package_manager.name).to eq "terraform"
        expect(package_manager.requirement).to be_nil
        expect(package_manager.version.to_s).to eq "1.10.0"
      end
    end
  end
end
