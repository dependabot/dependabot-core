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

      context "which times out" do
        before do
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_raise(Excon::Error::Timeout)
        end

        it { is_expected.to eq("registry.npmjs.org") }
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

  describe "#auth_headers" do
    subject { finder.auth_headers }

    it { is_expected.to eq({}) }

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

        it { is_expected.to eq({}) }
      end

      context "which lists the dependency" do
        before do
          body = fixture("javascript", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("Authorization" => "Bearer secret_token") }

        context "with a username/password style token" do
          before do
            credentials.last["token"] = "secret:token"
            body = fixture("javascript", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
              to_return(status: 200, body: body)
          end
          it { is_expected.to eq("Authorization" => "Basic c2VjcmV0OnRva2Vu") }
        end
      end
    end
  end

  describe "#dependency_url" do
    subject { finder.dependency_url }

    it { is_expected.to eq("https://registry.npmjs.org/etag") }

    context "with a private registry source" do
      let(:source) do
        { type: "private_registry", url: "http://npm.mine.io/dependabot" }
      end

      it { is_expected.to eq("http://npm.mine.io/dependabot/etag") }
    end
  end
end
