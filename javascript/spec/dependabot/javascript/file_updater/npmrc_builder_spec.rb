# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Javascript::FileUpdater::NpmrcBuilder do
  let(:npmrc_builder) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials,
      dependencies: dependencies
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end

  let(:dependencies) do
    []
  end

  describe "#npmrc_content" do
    subject(:npmrc_content) { npmrc_builder.npmrc_content }

    context "with an npmrc file" do
      let(:dependency_files) { project_dependency_files("javascript/npmrc_auth_token") }

      it "returns the npmrc file unaltered" do
        expect(npmrc_content)
          .to eq(fixture("projects", "javascript", "npmrc_auth_token", ".npmrc"))
      end

      context "when it needs to sanitize the authToken" do
        let(:dependency_files) { project_dependency_files("javascript/npmrc_env_auth_token") }

        it "removes the env variable use" do
          expect(npmrc_content)
            .to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
        end
      end

      context "when it needs auth sanitizing" do
        let(:dependency_files) { project_dependency_files("javascript/npmrc_env_auth") }

        it "removes the env variable use" do
          expect(npmrc_content)
            .to eq("@dependabot:registry=https://npm.fury.io/dependabot/\n")
        end
      end
    end

    context "with no private sources and some credentials" do
      let(:dependency_files) { project_dependency_files("javascript/simple") }

      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }), Dependabot::Credential.new({
          "type" => "npm_registry",
          "registry" => "registry.npmjs.org",
          "token" => "my_token"
        })]
      end

      it { is_expected.to eq("//registry.npmjs.org/:_authToken=my_token") }

      context "when using basic auth" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "registry.npmjs.org",
            "token" => "my:token"
          })]
        end

        it "includes Basic auth details" do
          expect(npmrc_content).to eq(
            "always-auth = true\n//registry.npmjs.org/:_auth=bXk6dG9rZW4="
          )
        end
      end

      context "when dealing with an npmrc file" do
        let(:dependency_files) { project_dependency_files("javascript/npmrc_auth_token") }

        it "appends to the npmrc file" do
          expect(npmrc_content)
            .to include(fixture("projects", "javascript", "npmrc_auth_token", ".npmrc"))
          expect(npmrc_content)
            .to end_with("\n\n//registry.npmjs.org/:_authToken=my_token")
        end
      end
    end

    context "when dealing with registry scope generation" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "npm_registry",
          "registry" => "registry.npmjs.org"
        }),
         Dependabot::Credential.new({
           "type" => "npm_registry",
           "registry" => "npm.pkg.github.com",
           "token" => "my_token"
         })]
      end

      context "when no packages resolve to the private registry" do
        let(:dependency_files) do
          project_dependency_files("javascript/simple")
        end

        it "adds only the token auth details" do
          expect(npmrc_content).to eql("//npm.pkg.github.com/:_authToken=my_token")
        end
      end
    end
  end
end
