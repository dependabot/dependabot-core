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
    
    context "registry source" do
      let(:name) { "hashicorp/consul/aws" }

      it { is_expected.to eq("hashicorp/consul/aws") }
    end

    context "registry source with special case" do
      let(:name) { "app.terraform.io/example-corp/k8s-cluster/azurerm" }

      it { is_expected.to eq("app.terraform.io/example-corp/k8s-cluster/azurerm") }
    end

    context "git source with ref" do
      let(:name) { "gitlab_ssh_without_protocol::gitlab::cloudposse/terraform-aws-jenkins::tags/0.4.0" }

      it { is_expected.to eq("gitlab_ssh_without_protocol::terraform-aws-jenkins") }
    end

    context "git source without ref" do
      let(:name) { "distribution_label::bitbucket::cloudposse/terraform-null-label" }

      it { is_expected.to eq("distribution_label::terraform-null-label") }
    end
  end

end
