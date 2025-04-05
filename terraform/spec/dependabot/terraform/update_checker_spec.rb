# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform"
require "dependabot/terraform/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Terraform::UpdateChecker do
  let(:source) do
    {
      type: "git",
      url: "https://github.com/cloudposse/terraform-null-label.git",
      branch: nil,
      ref: "tags/0.3.7"
    }
  end
  let(:requirement) { nil }
  let(:requirements) do
    [{ requirement: requirement, groups: [], file: "main.tf", source: source }]
  end
  let(:version) { "0.3.7" }
  let(:dependency_name) { "origin_label" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "terraform"
    )
  end
  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    context "with multiple file sources" do
      let(:requirements) do
        [
          { file: "./modules/main.tf", source: { type: "path", url: "./modules" }, requirement: nil, groups: [] },
          { file: "main.tf", source: { type: "path", url: "./" }, requirement: nil, groups: [] }
        ]
      end

      it "ignores the dependencies with file sources" do
        expect(latest_version).to be_nil
      end
    end

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null-label.git",
          branch: nil,
          ref: "tags/0.3.7"
        }
      end

      before do
        git_url = "https://github.com/cloudposse/terraform-null-label.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "terraform-null-label"),
            headers: git_header
          )
      end

      it { is_expected.to eq(Gem::Version.new("0.4.1")) }
    end

    context "with a registry dependency" do
      let(:source) do
        {
          type: "registry",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/consul/aws"
        }
      end

      before do
        url = "https://registry.terraform.io/v1/modules/" \
              "hashicorp/consul/aws/versions"
        registry_response = fixture(
          "registry_responses",
          "hashicorp_consul_aws_versions.json"
        )

        stub_request(
          :get, "https://registry.terraform.io/.well-known/terraform.json"
        ).to_return(status: 200, body: {
          "modules.v1": "/v1/modules/",
          "providers.v1": "/v1/providers/"
        }.to_json)
        stub_request(:get, url).to_return(status: 200, body: registry_response)
      end

      it { is_expected.to eq(Gem::Version.new("0.3.8")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 0.3.8, < 0.4.0"] }

        it { is_expected.to eq(Gem::Version.new("0.3.7")) }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null-label.git",
          branch: nil,
          ref: "tags/0.3.7"
        }
      end

      before do
        allow(checker).to receive(:latest_version).and_return("delegated")
      end

      it { is_expected.to eq("delegated") }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null-label.git",
          branch: nil,
          ref: "tags/0.3.7"
        }
      end

      before do
        git_url = "https://github.com/cloudposse/terraform-null-label.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "terraform-null-label"),
            headers: git_header
          )
      end

      it { is_expected.to be(true) }

      context "when no requirements can be unlocked" do
        subject { checker.can_update?(requirements_to_unlock: :none) }

        it { is_expected.to be_falsey }
      end
    end

    context "with a registry dependency" do
      let(:source) do
        {
          type: "registry",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/consul/aws"
        }
      end
      let(:version) { nil }
      let(:requirement) { "~> 0.2.1" }

      before do
        allow(checker).to receive(:latest_version)
          .and_return(Gem::Version.new("0.3.8"))
      end

      it { is_expected.to be(true) }

      context "when the requirement is already up-to-date" do
        let(:requirement) { "~> 0.3.1" }

        it { is_expected.to be_falsey }
      end

      context "when no requirements can be unlocked" do
        subject { checker.can_update?(requirements_to_unlock: :none) }

        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null-label.git",
          branch: nil,
          ref: ref
        }
      end
      let(:ref) { "tags/0.3.7" }

      before do
        git_url = "https://github.com/cloudposse/terraform-null-label.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(
            status: 200,
            body: fixture("git", "upload_packs", "terraform-null-label"),
            headers: git_header
          )
      end

      context "with a reference" do
        let(:ref) { "tags/0.3.7" }

        it "updates the reference" do
          expect(updated_requirements)
            .to eq(
              [{
                requirement: nil,
                groups: [],
                file: "main.tf",
                source: {
                  type: "git",
                  url: "https://github.com/cloudposse/terraform-null-label.git",
                  branch: nil,
                  ref: "tags/0.4.1"
                }
              }]
            )
        end
      end

      context "without a reference" do
        let(:ref) { nil }

        it { is_expected.to eq(requirements) }
      end

      context "with a git SHA as the latest version" do
        let(:ref) { "master" }

        it { is_expected.to eq(requirements) }
      end
    end

    context "with a registry dependency" do
      let(:source) do
        {
          type: "registry",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/consul/aws"
        }
      end
      let(:requirement) { "~> 0.2.1" }

      before do
        allow(checker).to receive(:latest_version)
          .and_return(Gem::Version.new("0.3.8"))
      end

      it "updates the requirement" do
        expect(updated_requirements)
          .to eq(
            [{
              requirement: "~> 0.3.8",
              groups: [],
              file: "main.tf",
              source: {
                type: "registry",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/consul/aws"
              }
            }]
          )
      end

      context "when the requirement is already up-to-date" do
        let(:requirement) { "~> 0.3.1" }

        it { is_expected.to eq(requirements) }
      end
    end

    context "with a provider", :vcr do
      let(:source) do
        {
          type: "provider",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/aws"
        }
      end
      let(:requirement) { "~> 2.0" }

      it "updates the requirement" do
        expect(updated_requirements)
          .to eq(
            [{
              requirement: "~> 3.42",
              groups: [],
              file: "main.tf",
              source: {
                type: "provider",
                registry_hostname: "registry.terraform.io",
                module_identifier: "hashicorp/aws"
              }
            }]
          )
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }

    context "with a source that came from an http proxy" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/cloudposse/terraform-null-label.git",
          branch: nil,
          ref: "tags/0.3.7",
          proxy_url: "https://my.example.com"
        }
      end

      it { is_expected.to be(false) }
    end
  end
end
