# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/terraform/terraform"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Terraform::Terraform do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "origin_label",
      version: "tags/0.4.1",
      previous_version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "main.tf",
        source: {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null.git",
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
          url: "https://github.com/cloudposse/terraform-null.git",
          branch: nil,
          ref: "tags/0.3.7"
        }
      }],
      package_manager: "terraform"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "rtfeldman/elm-css" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    it { is_expected.to eq("https://github.com/cloudposse/terraform-null") }

    context "with a registry-based dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "hashicorp/consul/aws",
          version: "0.3.8",
          previous_version: "0.1.0",
          requirements: [{
            requirement: "0.3.8",
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
      end

      let(:registry_url) do
        "https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8"
      end
      let(:registry_response) do
        fixture(
          "terraform",
          "registry_responses",
          "hashicorp_consul_aws_0.3.8.json"
        )
      end
      before do
        stub_request(:get, registry_url).
          to_return(status: 200, body: registry_response)
      end

      it do
        is_expected.to eq("https://github.com/hashicorp/terraform-aws-consul")
      end
    end
  end
end
