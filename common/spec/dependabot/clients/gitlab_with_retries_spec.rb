# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/gitlab_with_retries"

RSpec.describe Dependabot::Clients::GitlabWithRetries do
  let(:client) do
    described_class.new(
      endpoint: "https://gitlab.com/api/v4",
      private_token: access_token
    )
  end
  let(:access_token) { "my-token" }

  describe "retrying a method" do
    subject { client.get_file("some/repo", "important_path.json", "sha") }

    # rubocop:disable Style/BracesAroundHashParameters
    context "when the request has to be retried" do
      before do
        repo_url = "https://gitlab.com/api/v4/projects/some%2Frepo/repository"
        stub_request(:get, "#{repo_url}/files/important_path.json?ref=sha").
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
