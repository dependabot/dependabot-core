# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/github_with_retries"

RSpec.describe Dependabot::Clients::GithubWithRetries do
  let(:client) { described_class.new(access_token: access_token) }
  let(:access_token) { "my-token" }

  describe "retrying a method that mutates args" do
    subject { client.contents("some/repo", path: "important_path.json") }

    context "when the request has to be retried" do
      before do
        repo_url = "https://api.github.com/repos/some/repo"
        stub_request(:get, "#{repo_url}/contents/important_path.json").
          with(headers: { "Authorization" => "token my-token" }).
          to_return(
            { status: 502, headers: { "content-type" => "application/json" } },
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      its(:name) { is_expected.to eq("Gemfile") }
    end
  end

  describe "with multiple possible access tokens" do
    let(:access_tokens) { %w(my-token my-other-token) }
    let(:client) { described_class.new(access_tokens: access_tokens) }
    subject { client.contents("some/repo", path: "important_path.json") }

    context "when the request has to be retried" do
      before do
        repo_url = "https://api.github.com/repos/some/repo"
        stub_request(:get, "#{repo_url}/contents/important_path.json").
          with(headers: { "Authorization" => "token my-token" }).
          to_return(status: 404)
        stub_request(:get, "#{repo_url}/contents/important_path.json").
          with(headers: { "Authorization" => "token my-other-token" }).
          to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      its(:name) { is_expected.to eq("Gemfile") }
    end
  end

  describe ".open_timeout_in_seconds" do
    context "when DEPENDABOT_OPEN_TIMEOUT_IN_SECONDS is set" do
      it "returns the provided value" do
        override_value = 10
        stub_const("ENV", ENV.to_hash.merge("DEPENDABOT_OPEN_TIMEOUT_IN_SECONDS" => override_value))

        expect(described_class.open_timeout_in_seconds).to eq(override_value)
      end
    end

    context "when ENV does not provide an override" do
      it "falls back to a default value" do
        expect(described_class.open_timeout_in_seconds).
          to eq(described_class::DEFAULT_OPEN_TIMEOUT_IN_SECONDS)
      end
    end
  end

  describe ".read_timeout_in_seconds" do
    context "when DEPENDABOT_READ_TIMEOUT_IN_SECONDS is set" do
      it "returns the provided value" do
        override_value = 10
        stub_const("ENV", ENV.to_hash.merge("DEPENDABOT_READ_TIMEOUT_IN_SECONDS" => override_value))

        expect(described_class.read_timeout_in_seconds).to eq(override_value)
      end
    end

    context "when ENV does not provide an override" do
      it "falls back to a default value" do
        expect(described_class.read_timeout_in_seconds).
          to eq(described_class::DEFAULT_READ_TIMEOUT_IN_SECONDS)
      end
    end
  end
end
