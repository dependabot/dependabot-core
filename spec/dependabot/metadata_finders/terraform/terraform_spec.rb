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
  end
end
