# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/update_checker/registry_finder"

RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::RegistryFinder do
  subject(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      npmrc_file: npmrc_file,
      yarnrc_file: yarnrc_file,
      yarnrc_yml_file: yarnrc_yml_file
    )
  end
  let(:npmrc_file) { nil }
  let(:yarnrc_file) { nil }
  let(:yarnrc_yml_file) { nil }
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
      name: "etag",
      version: "1.0.0",
      requirements: [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: [],
        source: source
      }],
      package_manager: "npm_and_yarn"
    )
  end
  let(:source) { nil }

  describe "registry_from_rc" do
    subject { finder.registry_from_rc(dependency_name) }

    let(:dependency_name) { "some_dep" }

    it { is_expected.to eq("https://registry.npmjs.org") }

    context "with no rc and with credentials" do
      let(:credentials) do
        [{
          "type" => "npm_registry",
          "registry" => "http://example.com",
          "replaces-base" => true
        }]
      end

      it { is_expected.to eq("http://example.com") }
    end

    context "with a global npm registry" do
      let(:npmrc_file) { Dependabot::DependencyFile.new(name: ".npmrc", content: "registry=http://example.com") }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a global yarn registry" do
      let(:yarnrc_file) { Dependabot::DependencyFile.new(name: ".yarnrc", content: 'registry "http://example.com"') }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a global yarn registry not wrapped in quotes" do
      let(:yarnrc_file) { Dependabot::DependencyFile.new(name: ".yarnrc", content: "registry http://example.com") }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a global yarn berry registry" do
      let(:yarnrc_yml_file) do
        Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: 'npmRegistryServer: "https://example.com"')
      end

      it { is_expected.to eq("https://example.com") }
    end

    context "with a scoped npm registry" do
      let(:dependency_name) { "@dependabot/some_dep" }
      let(:npmrc_file) { Dependabot::DependencyFile.new(name: ".npmrc", content: "@dependabot:registry=http://example.com") }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a scoped yarn registry" do
      let(:dependency_name) { "@dependabot/some_dep" }
      let(:yarnrc_file) { Dependabot::DependencyFile.new(name: ".yarnrc", content: '"@dependabot:registry" "http://example.com"') }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a scoped yarn registry not wrapped in quotes" do
      let(:dependency_name) { "@dependabot/some_dep" }
      let(:yarnrc_file) { Dependabot::DependencyFile.new(name: ".yarnrc", content: '"@dependabot:registry" http://example.com') }

      it { is_expected.to eq("http://example.com") }
    end

    context "with a scoped yarn berry registry" do
      let(:dependency_name) { "@dependabot/some_dep" }
      let(:yarnrc_yml_content) do
        <<~YARNRC
          npmScopes:
            dependabot:
              npmRegistryServer: "https://example.com"
        YARNRC
      end
      let(:yarnrc_yml_file) { Dependabot::DependencyFile.new(name: ".yarnrc", content: yarnrc_yml_content) }

      it { is_expected.to eq("https://example.com") }
    end
  end

  describe "registry" do
    subject { finder.registry }

    it { is_expected.to eq("registry.npmjs.org") }

    context "with credentials for a private registry" do
      let(:credentials) do
        [{
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }, {
          "type" => "npm_registry",
          "registry" => "https://npm.fury.io/dependabot",
          "token" => "secret_token"
        }]
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
          body = fixture("gemfury_responses", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("https://npm.fury.io/dependabot") }

        context "but returns HTML" do
          before do
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 200, body: "<html>Hello!</html>")
          end

          it { is_expected.to eq("registry.npmjs.org") }
        end

        context "but doesn't include auth" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "npm.fury.io/dependabot"
            }]
          end

          before do
            body = fixture("gemfury_responses", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              to_return(status: 200, body: body)
          end

          it { is_expected.to eq("npm.fury.io/dependabot") }
        end
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

    context "with a .npmrc file" do
      let(:npmrc_file) do
        project_dependency_files(project_name).find { |f| f.name == ".npmrc" }
      end
      let(:project_name) { "npm6/npmrc_auth_token" }

      before do
        body = fixture("gemfury_responses", "gemfury_response_etag.json")
        stub_request(:get, "https://npm.fury.io/dependabot/etag").
          with(headers: { "Authorization" => "Bearer secret_token" }).
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq("npm.fury.io/dependabot") }

      context "with an environment variable URL" do
        let(:project_name) { "npm6/npmrc_env_url" }
        it { is_expected.to eq("registry.npmjs.org") }
      end

      context "that includes a carriage return" do
        let(:project_name) { "npm6/npmrc_auth_token_carriage_return" }
        it { is_expected.to eq("npm.fury.io/dependabot") }
      end
    end

    context "with a space in registry url" do
      context "in .npmrc file" do
        let(:npmrc_file) do
          project_dependency_files(project_name).find { |f| f.name == ".npmrc" }
        end
        let(:project_name) { "npm6/npmrc_auth_token_with_space" }

        before do
          body = fixture("gemfury_responses", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot%20with%20space/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("npm.fury.io/dependabot%20with%20space") }
      end

      context "in .yarnrc file" do
        let(:yarnrc_file) do
          project_dependency_files(project_name).find { |f| f.name == ".yarnrc" }
        end
        let(:project_name) { "yarn/yarnrc_global_registry_with_space" }

        before do
          url = "https://npm-proxy.fury.io/password/dependabot%20with%20space/etag"
          body = fixture("gemfury_responses", "gemfury_response_etag.json")

          stub_request(:get, url).to_return(status: 200, body: body)
        end

        it { is_expected.to eq("npm-proxy.fury.io/password/dependabot%20with%20space") }
      end
    end

    context "with a .yarnrc file" do
      let(:yarnrc_file) do
        project_dependency_files(project_name).find { |f| f.name == ".yarnrc" }
      end
      let(:project_name) { "yarn/yarnrc_global_registry" }

      before do
        url = "https://npm-proxy.fury.io/password/dependabot/etag"
        body = fixture("gemfury_responses", "gemfury_response_etag.json")

        stub_request(:get, url).to_return(status: 200, body: body)
      end

      it { is_expected.to eq("npm-proxy.fury.io/password/dependabot") }

      context "that can't be reached" do
        before do
          url = "https://npm-proxy.fury.io/password/dependabot/etag"
          stub_request(:get, url).to_return(status: 401, body: "")
        end

        # Since this registry is declared at the global registry, in the absence
        # of other information we should still us it (and *not* flaa back to
        # registry.npmjs.org)
        it { is_expected.to eq("npm-proxy.fury.io/password/dependabot") }
      end
    end

    context "with a .yarnrc.yml file" do
      let(:yarnrc_yml_file) do
        project_dependency_files(project_name).find { |f| f.name == ".yarnrc.yml" }
      end
      let(:project_name) { "yarn_berry/yarnrc_global_registry" }

      before do
        url = "https://npm-proxy.fury.io/password/dependabot/etag"
        body = fixture("gemfury_responses", "gemfury_response_etag.json")

        stub_request(:get, url).to_return(status: 200, body: body)
      end

      it { is_expected.to eq("npm-proxy.fury.io/password/dependabot") }

      context "that can't be reached" do
        before do
          url = "https://npm-proxy.fury.io/password/dependabot/etag"
          stub_request(:get, url).to_return(status: 401, body: "")
        end

        # Since this registry is declared at the global registry, in the absence
        # of other information we should still us it (and *not* flaa back to
        # registry.npmjs.org)
        it { is_expected.to eq("npm-proxy.fury.io/password/dependabot") }
      end
    end

    context "with a private registry source" do
      let(:source) do
        { type: "registry", url: "https://npm.fury.io/dependabot" }
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
          "type" => "npm_registry",
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
          body = fixture("gemfury_responses", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/etag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
        end

        it { is_expected.to eq("Authorization" => "Bearer secret_token") }

        context "with a username/password style token" do
          before do
            credentials.last["token"] = "secret:token"
            body = fixture("gemfury_responses", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
              to_return(status: 200, body: body)
          end
          it { is_expected.to eq("Authorization" => "Basic c2VjcmV0OnRva2Vu") }
        end

        context "with a token that is in encoded username:password format" do
          before do
            credentials.last["token"] = Base64.encode64("secret:token")
            body = fixture("gemfury_responses", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
              to_return(status: 200, body: body)
          end
          it { is_expected.to eq("Authorization" => "Basic c2VjcmV0OnRva2Vu") }
        end

        context "without a token" do
          before do
            credentials.last.delete("token")
            body = fixture("gemfury_responses", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              to_return(status: 404)
            stub_request(:get, "https://npm.fury.io/dependabot/etag").
              to_return(status: 200, body: body)
          end

          it { is_expected.to eq({}) }
        end
      end
    end
  end

  describe "#dependency_url" do
    subject { finder.dependency_url }

    it { is_expected.to eq("https://registry.npmjs.org/etag") }

    context "with a private registry source" do
      let(:source) do
        { type: "registry", url: "http://npm.mine.io/dependabot/" }
      end

      it { is_expected.to eq("http://npm.mine.io/dependabot/etag") }
    end

    context "when multiple js sources are provided" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "example",
          version: "1.0.0",
          requirements: requirements,
          package_manager: "npm_and_yarn"
        )
      end

      let(:requirements) do
        [
          {
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: { type: "registry", url: "https://registry.npmjs.org" }
          },
          {
            file: "shared-lib/package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.yarnpkg.com" }
          }
        ]
      end

      it "allows multiple sources" do
        expect { subject }.not_to raise_error
      end
    end

    context "when a public registry and a private registry is detected" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "example",
          version: "1.0.0",
          requirements: requirements,
          package_manager: "npm_and_yarn"
        )
      end

      let(:requirements) do
        [
          {
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.npmjs.org" }
          },
          {
            file: "shared-lib/package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.example.org" }
          }
        ]
      end

      it "returns the private registry url" do
        expect(subject).to eql("https://registry.example.org/example")
      end
    end
  end
end
