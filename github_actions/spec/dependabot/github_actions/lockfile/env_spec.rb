# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/github_actions/lockfile"

RSpec.describe Dependabot::GithubActions::Lockfile::Env do
  def cred(hash)
    Dependabot::Credential.new(hash)
  end

  describe ".build" do
    context "with no github credential (hosted/tokenless mode)" do
      it "sets a non-empty dummy GH_TOKEN so go-gh runs and the proxy injects auth" do
        env = described_class.build([])
        expect(env["GH_TOKEN"]).to eq("x-access-token")
        expect(env["GH_TOKEN"]).not_to be_empty
      end
    end

    context "with a real github.com credential (proxyless mode)" do
      let(:credentials) do
        [cred(
          { "type" => "git_source", "host" => "github.com",
            "username" => "x-access-token", "password" => "real-token" }
        )]
      end

      it "passes the real token through as GH_TOKEN" do
        expect(described_class.build(credentials)["GH_TOKEN"]).to eq("real-token")
      end
    end

    context "with both an app token and a deliberate token" do
      let(:credentials) do
        [
          cred({ "type" => "git_source", "host" => "github.com", "password" => "v1.app-token" }),
          cred({ "type" => "git_source", "host" => "github.com", "password" => "pat-token" })
        ]
      end

      it "prefers the non-app token" do
        expect(described_class.build(credentials)["GH_TOKEN"]).to eq("pat-token")
      end
    end

    context "with a GHES credential" do
      let(:credentials) do
        [cred({ "type" => "git_source", "host" => "ghe.example.com", "password" => "ghes-token" })]
      end

      it "sets GH_HOST and GH_ENTERPRISE_TOKEN" do
        env = described_class.build(credentials)
        expect(env["GH_HOST"]).to eq("ghe.example.com")
        expect(env["GH_ENTERPRISE_TOKEN"]).to eq("ghes-token")
      end
    end
  end
end
