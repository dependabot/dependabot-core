# typed: false
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/nuget/update_checker/repository_finder"

RSpec.describe Dependabot::Nuget::RepositoryFinder do
  describe "#credential_repositories" do
    subject(:credential_repositories) do
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
    end

    context "when credentials token is `nil`" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://api.nuget.org/v3/index.json" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://api.nuget.org/v3/index.json", token: nil }]
        )
      end
    end

    context "when credentials token is `nil`, username is `nil`, and password is non-empty" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "password" => "github_pat_secret" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: ":github_pat_secret" }]
        )
      end
    end

    context "when credentials token is `nil`, username and password are non-empty" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "username" => "user",
           "password" => "password" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: "user:password" }]
        )
      end
    end

    context "when credentials token, username, and password are all non-empty" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "github_pat_secret",
           "username" => "user", "password" => "password" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: "github_pat_secret" }]
        )
      end
    end

    context "when credentials token is access token" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "github_pat_secret" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: "github_pat_secret" }]
        )
      end
    end

    context "when credentials token is basic access auth" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => "user:password" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: "user:password" }]
        )
      end
    end

    context "when credentials token is basic access auth with no username" do
      let(:credentials) do
        [{ "type" => "nuget_feed", "url" => "https://my.nuget.com/v3/index.json", "token" => ":password_only" }]
      end

      it "returns the repository with credentials as a token" do
        expect(credential_repositories).to eq(
          [{ url: "https://my.nuget.com/v3/index.json", token: ":password_only" }]
        )
      end
    end
  end
end
