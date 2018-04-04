# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_client_with_retries"

RSpec.describe Dependabot::GithubClientWithRetries do
  let(:client) { described_class.new(access_token: access_token) }
  let(:access_token) { "my-token" }

  describe "retrying a method that mutates args" do
    subject { client.contents("some/repo", path: "important_path.json") }

    # rubocop:disable Style/BracesAroundHashParameters
    context "when the request has to be retried" do
      before do
        repo_url = "https://api.github.com/repos/some/repo"
        stub_request(:get, "#{repo_url}/contents/important_path.json").
          with(headers: { "Authorization" => "token my-token" }).
          to_return(
            { status: 502, headers: { "content-type" => "application/json" } },
            {
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            }
          )
      end

      its(:name) { is_expected.to eq("Gemfile") }
    end
    # rubocop:enable Style/BracesAroundHashParameters
  end
end
