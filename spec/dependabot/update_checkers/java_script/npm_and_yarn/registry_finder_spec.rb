# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java_script/npm_and_yarn/registry_finder"

tested_module = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe tested_module::RegistryFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      npmrc_file: npmrc_file
    )
  end
  let(:npmrc_file) { nil }
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "etag",
      version: "1.0.0",
      requirements: [
        {
          file: "package.json",
          requirement: "^1.0.0",
          groups: [],
          source: source
        }
      ],
      package_manager: "npm_and_yarn"
    )
  end
  let(:source) { nil }

  describe "registry" do
    subject { finder.registry }

    it { is_expected.to eq("registry.npmjs.org") }

    context "with credentials for a private registry" do
      before do
        credentials << {
          "registry" => "npm.fury.io/dependabot",
          "token" => "secret_token"
        }
      end

      context "which doesn't list the dependency" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 404)
        end

        it { is_expected.to eq("registry.npmjs.org") }
      end

      context "which lists the dependency" do
        before do
          body = fixture("javascript", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("npm.fury.io/dependabot") }
      end
    end

    context "with a private registry source" do
      let(:source) do
        { type: "private_registry", url: "https://npm.fury.io/dependabot" }
      end

      it { is_expected.to eq("npm.fury.io/dependabot") }
    end

    context "with a git source" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/jonschlinkert/is-number",
          branch: nil,
          ref: "v1.0.0"
        }
      end

      it { is_expected.to eq("registry.npmjs.org") }
    end
  end

  describe "#auth_token" do
    subject { finder.auth_token }

    it { is_expected.to be_nil }

    context "with credentials for a private registry" do
      before do
        credentials << {
          "registry" => "npm.fury.io/dependabot",
          "token" => "secret_token"
        }
      end

      context "which doesn't list the dependency" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 404)
        end

        it { is_expected.to be_nil }
      end

      context "which lists the dependency" do
        before do
          body = fixture("javascript", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("secret_token") }
      end
    end
  end

  describe "#dependency_url" do
    subject { finder.dependency_url }

    it { is_expected.to eq("https://registry.npmjs.org/etag") }

    context "with a private registry source" do
      let(:source) do
        { type: "private_registry", url: "http://npm.fury.io/dependabot" }
      end

      it { is_expected.to eq("http://npm.fury.io/dependabot/etag") }
    end
  end
end
