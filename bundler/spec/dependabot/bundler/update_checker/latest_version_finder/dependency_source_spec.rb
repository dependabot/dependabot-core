# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/update_checker"

RSpec.describe Dependabot::Bundler::UpdateChecker::LatestVersionFinder::DependencySource do
  let(:project_name) { "git_source" }
  let(:files) { project_dependency_files(File.join("bundler2", project_name)) }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "irrelevant",
      version: "1.0.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.0",
          groups: ["default"],
          source: nil
        }
      ],
      package_manager: "bundler"
    )
  end

  let(:source) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      options: {}
    )
  end

  describe "#inaccessible_git_dependencies", :vcr do
    subject(:inaccessible_git_dependencies) { source.inaccessible_git_dependencies }

    it "is empty when all dependencies are accessible" do
      expect(inaccessible_git_dependencies).to be_empty
    end

    context "with inaccessible dependency", :vcr do
      let(:project_name) { "private_git_source" }

      it "includes inaccessible dependency" do
        expect(inaccessible_git_dependencies.size).to eq(1)
        expect(inaccessible_git_dependencies.first).to eq(
          {
            "auth_uri" => "https://x-access-token:token@github.com/no-exist-sorry/prius.git/info/refs?service=git-upload-pack",
            "uri" => "git@github.com:no-exist-sorry/prius"
          }
        )
      end
    end

    context "with non-URI dependency", :vcr do
      let(:project_name) { "git_source_invalid_github" }

      it "includes invalid dependency" do
        expect(inaccessible_git_dependencies.size).to eq(1)
        expect(inaccessible_git_dependencies.first).to eq(
          {
            "auth_uri" => "dependabot-fixtures/business.git/info/refs?service=git-upload-pack",
            "uri" => "dependabot-fixtures/business"
          }
        )
      end
    end
  end

  describe "#dependency_rubygems_uri" do
    subject(:uri) { source.send(:dependency_rubygems_uri) }

    context "without replaces_base credential" do
      it "returns the rubygems.org URI" do
        expect(uri).to eq("https://rubygems.org/api/v1/versions/irrelevant.json")
      end
    end

    context "with a replaces_base rubygems_server credential" do
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          Dependabot::Credential.new(
            {
              "type" => "rubygems_server",
              "host" => "gems.example.com",
              "token" => "secret",
              "replaces-base" => true
            }
          )
        ]
      end

      it "returns the private registry URI" do
        expect(uri).to eq("https://gems.example.com/api/v1/versions/irrelevant.json")
      end
    end

    context "with a non-replaces_base rubygems_server credential" do
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          Dependabot::Credential.new(
            {
              "type" => "rubygems_server",
              "host" => "gems.example.com",
              "token" => "secret"
            }
          )
        ]
      end

      it "returns the rubygems.org URI" do
        expect(uri).to eq("https://rubygems.org/api/v1/versions/irrelevant.json")
      end
    end
  end
end
