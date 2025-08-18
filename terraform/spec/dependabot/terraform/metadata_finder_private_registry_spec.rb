# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/terraform/metadata_finder"

RSpec.describe Dependabot::Terraform::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_name) { "company/vpc" }
  let(:credentials) do
    [
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "github-token"
      },
      {
        "type" => "terraform_registry",
        "host" => "app.terraform.io",
        "token" => "registry-token"
      }
    ]
  end

  describe "private registry changelog support" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "1.2.0",
        previous_version: "1.1.0",
        requirements: [{
          requirement: "~> 1.2",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "app.terraform.io",
            module_identifier: "company/vpc/aws"
          }
        }],
        previous_requirements: [{
          requirement: "~> 1.1",
          groups: [],
          file: "main.tf",
          source: {
            type: "registry",
            registry_hostname: "app.terraform.io",
            module_identifier: "company/vpc/aws"
          }
        }],
        package_manager: "terraform"
      )
    end

    context "when source is successfully resolved" do
      let(:github_source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "company/terraform-aws-vpc",
          directory: nil,
          branch: nil,
          commit: nil
        )
      end

      before do
        # Mock the registry client to return a GitHub source
        registry_client = instance_double(Dependabot::Terraform::RegistryClient)
        allow(Dependabot::Terraform::RegistryClient).to receive(:new)
          .and_return(registry_client)
        allow(registry_client).to receive(:source)
          .and_return(github_source)

        # Mock the private registry logger
        allow(Dependabot::Terraform::PrivateRegistryLogger)
          .to receive(:log_registry_operation)
        allow(Dependabot::Terraform::PrivateRegistryLogger)
          .to receive(:log_registry_error)
      end

      describe "#changelog_text" do
        it "uses enhanced credentials for private registry dependencies" do
          expect(Dependabot::MetadataFinders::Base::ChangelogFinder)
            .to receive(:new) do |args|
              # Verify that enhanced credentials are passed
              expect(args[:credentials]).to include(
                hash_including("type" => "git_source", "host" => "github.com")
              )
              instance_double(Dependabot::MetadataFinders::Base::ChangelogFinder,
                              changelog_text: "Changelog content")
            end

          result = finder.changelog_text
          expect(result).to eq("Changelog content")
        end

        it "falls back to base implementation for non-registry dependencies" do
          # Change dependency to git type
          allow(dependency).to receive(:source_type).and_return("git")
          
          expect(finder).to receive(:super).and_call_original
          finder.changelog_text
        end
      end

      describe "#releases_text" do
        it "uses enhanced credentials for private registry dependencies" do
          expect(Dependabot::MetadataFinders::Base::ReleaseFinder)
            .to receive(:new) do |args|
              # Verify that enhanced credentials are passed
              expect(args[:credentials]).to include(
                hash_including("type" => "git_source", "host" => "github.com")
              )
              instance_double(Dependabot::MetadataFinders::Base::ReleaseFinder,
                              releases_text: "Release notes content")
            end

          result = finder.releases_text
          expect(result).to eq("Release notes content")
        end
      end

      describe "#enhanced_credentials_for_changelog" do
        it "filters credentials for source repository access" do
          # Set up the source on the finder
          allow(finder).to receive(:source).and_return(github_source)

          enhanced_creds = finder.send(:enhanced_credentials_for_changelog)

          # Should include git_source credentials for github.com
          github_cred = enhanced_creds.find { |c| c["type"] == "git_source" }
          expect(github_cred).not_to be_nil
          expect(github_cred["host"]).to eq("github.com")

          # Should include terraform_registry credentials for app.terraform.io
          registry_cred = enhanced_creds.find { |c| c["type"] == "terraform_registry" }
          expect(registry_cred).not_to be_nil
          expect(registry_cred["host"]).to eq("app.terraform.io")
        end
      end
    end
  end
end