# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform"
require_common_spec "shared_examples_for_autoloading"

RSpec.describe Dependabot::Terraform do
  it_behaves_like "it registers the required classes", "terraform"

  describe "Dependency#display_name" do
    subject(:display_name) do
      Dependabot::Dependency.new(**dependency_args).display_name
    end

    let(:dependency_args) do
      { name: name, requirements: [], package_manager: "terraform" }
    end

    context "when dealing with a provider source" do
      let(:name) { "hashicorp/aws" }

      it { is_expected.to eq("hashicorp/aws") }
    end

    context "when dealing with a provider source with special chars" do
      let(:name) { "terraform.example.com/examplecorp/ourcloud" }

      it { is_expected.to eq("terraform.example.com/examplecorp/ourcloud") }
    end

    context "when dealing with registry source" do
      let(:name) { "hashicorp/consul/aws" }

      it { is_expected.to eq("hashicorp/consul/aws") }
    end

    context "when dealing with a registry source with special chars" do
      let(:name) { "app.terraform.io/example-corp/k8s-cluster/azurerm" }

      it { is_expected.to eq("app.terraform.io/example-corp/k8s-cluster/azurerm") }
    end

    context "when dealing with a git source with ref" do
      let(:name) { "gitlab_ssh_without_protocol::gitlab::cloudposse/terraform-aws-jenkins::tags/0.4.0" }

      it { is_expected.to eq("gitlab_ssh_without_protocol::terraform-aws-jenkins") }
    end

    context "when dealing with a git source without ref" do
      let(:name) { "distribution_label::bitbucket::cloudposse/terraform-null-label" }

      it { is_expected.to eq("distribution_label::terraform-null-label") }
    end

    context "when dealing with a git unknown source with ref" do
      let(:name) do
        "module_name::git_provider::repo_name/git_repo(9685A3B07E8D9C45BE0A3D92B02F13978FB311D8)::tags/0.1.0"
      end

      it { is_expected.to eq("module_name::git_repo") }
    end

    context "when dealing with a git unknown source without ref" do
      let(:name) { "module_name::git_provider::repo_name/git_repo(9685A3B07E8D9C45BE0A3D92B02F13978FB311D8)" }

      it { is_expected.to eq("module_name::git_repo") }
    end
  end
end
