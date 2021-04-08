# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/utils/auth_headers_finder"

RSpec.describe Dependabot::Maven::Utils::AuthHeadersFinder do
  subject(:finder) { described_class.new(credentials) }
  let(:credentials) do
    [
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      },
      {
        "type" => "git_source",
        "host" => "gitlab.com",
        "username" => "x-access-token",
        "password" => "token"
      },
      {
        "type" => "git_source",
        "host" => "custom-gitlab.com",
        "username" => "x-access-token",
        "password" => "custom-token"
      },
      {
        "type" => "maven_repository",
        "url" => "https://repo.maven.apache.org/maven2",
        "username" => "dependabot",
        "password" => "dependabotPassword"
      }
    ]
  end

  describe "#auth_headers" do
    subject(:found_auth_headers) { finder.auth_headers(maven_repo_url) }
    let(:maven_repo_url) do
      "https://custom.repo.org/maven2"
    end

    context "with no matching credentials" do
      it { is_expected.to eq({}) }
    end

    context "with matching credentials" do
      let(:maven_repo_url) do
        "https://repo.maven.apache.org/maven2"
      end

      encoded_token = Base64.strict_encode64("dependabot:dependabotPassword")

      it { is_expected.to eq({ "Authorization" => "Basic #{encoded_token}" }) }
    end

    context "with matching gitlab credentials" do
      let(:maven_repo_url) do
        "https://gitlab.com/api/v4/groups/some-group/-/packages/maven"
      end

      it { is_expected.to eq({ "Private-Token" => "token" }) }

      context "for a private gitlab instance" do
        let(:maven_repo_url) do
          "https://custom-gitlab.com/api/v4/groups/some-group/-/packages/maven"
        end

        it { is_expected.to eq({ "Private-Token" => "custom-token" }) }
      end

      context "and gitlab credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "gitlab.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "maven_repository",
              "url" => "https://gitlab.com/api/v4/groups/some-group/-/packages/maven",
              "username" => "dependabot",
              "password" => "dependabotPassword"
            }
          ]
        end
        let(:maven_repo_url) do
          "https://gitlab.com/api/v4/groups/some-group/-/packages/maven"
        end

        encoded_token = Base64.encode64("dependabot:dependabotPassword").delete("\n")

        it { is_expected.to eq({ "Authorization" => "Basic #{encoded_token}" }) }
      end

      context "but not a gitlab maven repo" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "gitlab.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ]
        end
        let(:maven_repo_url) do
          "https://gitlab.com/api/v4/groups/some-group/-/packages/npm"
        end

        it { is_expected.to eq({}) }
      end
    end
  end
end
