# typed: false
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/update_checker/repository_finder"

RSpec.describe Dependabot::Nuget::RepositoryFinder do
  describe "#credential_repositories" do
    subject(:result) {
      described_class.new(
        dependency: Dependabot::Dependency.new(
          name: "Microsoft.Extensions.DependencyModel",
          version: "1.0.0",
          requirements: [],
          package_manager: "nuget"
        ),
        credentials: credentials,
        config_files: []
      ).send(:credential_repositories)
    }

    context "when credentials token is `nil`" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://api.nuget.org/v3/index.json" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://api.nuget.org/v3/index.json", :token => nil }]
        )
      }
    end

    context "when credentials token is `nil`, username is `nil`, and password is non-empty" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "password" => "github_pat_secret" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => ":github_pat_secret" }]
        )
      }
    end

    context "when credentials token is `nil`, username and password are non-empty" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "username" => "user",
           "password" => "password" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => "user:password" }]
        )
      }
    end

    context "when credentials token, username, and password are all non-empty" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "github_pat_secret",
           "username" => "user", "password" => "password" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => "github_pat_secret" }]
        )
      }
    end

    context "when credentials token is access token" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "github_pat_secret" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => "github_pat_secret" }]
        )
      }
    end

    context "when credentials token is basic access auth" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "user:password" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => "user:password" }]
        )
      }
    end

    context "when credentials token is basic access auth with no username" do
      let(:credentials) {
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => ":password_only" }]
      }
      it {
        is_expected.to eq(
          [{ :url => "https://my.nuget.com/v3/index.json", :token => ":password_only" }]
        )
      }
    end
  end
end
