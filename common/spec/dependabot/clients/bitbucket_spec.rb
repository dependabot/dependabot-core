# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/bitbucket"

RSpec.describe Dependabot::Clients::Bitbucket do
  let(:access_token) { "access_token" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "bitbucket.org",
      "username" => nil,
      "token" => access_token
    }]
  end
  let(:branch) { "master" }
  let(:repo) { "test/repo" }
  let(:base_url) { "https://bitbucket.org/test/repo" }
  let(:api_base_url) { "https://api.bitbucket.org/2.0/repositories/" }
  let(:source) { Dependabot::Source.from_url(base_url + "/src/master/") }
  let(:client) do
    described_class.for_source(source: source, credentials: credentials)
  end

  describe "#default_reviewers" do
    subject do
      client.default_reviewers(repo)
    end

    let(:default_reviewers_url) { api_base_url + repo + "/default-reviewers?pagelen=100&fields=values.uuid,next" }

    context "when no default reviewers are defined" do
      before do
        stub_request(:get, default_reviewers_url).
          with(headers: { "Authorization" => "Bearer #{access_token}" }).
          to_return(status: 200, body: fixture("bitbucket", "default_reviewers_no_data.json"))
      end

      specify { expect { subject }.to_not raise_error }

      it { is_expected.to eq([]) }
    end

    context "when default reviewers are defined" do
      before do
        stub_request(:get, default_reviewers_url).
          with(headers: { "Authorization" => "Bearer #{access_token}" }).
          to_return(status: 200, body: fixture("bitbucket", "default_reviewers_with_data.json"))
      end

      specify { expect { subject }.to_not raise_error }

      it { is_expected.to eq([{ uuid: "{00000000-0000-0000-0000-000000000001}" }]) }
    end
  end

  describe "#create_pull_request" do
    subject do
      client.create_pull_request(repo, "pr_name", "source_branch", "target_branch", "pr_description", nil)
    end

    let(:default_reviewers_url) { api_base_url + repo + "/default-reviewers?pagelen=100&fields=values.uuid,next" }
    let(:pull_request_url) { api_base_url + repo + "/pullrequests" }

    context "create pull request successfully" do
      before do
        stub_request(:get, default_reviewers_url).
          with(headers: { "Authorization" => "Bearer #{access_token}" }).
          to_return(status: 201, body: fixture("bitbucket", "default_reviewers_no_data.json"))

        stub_request(:post, pull_request_url).
          with(
            body: "{\"title\":\"pr_name\",\"source\":{\"branch\":{\"name\":\"source_branch\"}}," \
              "\"destination\":{\"branch\":{\"name\":\"target_branch\"}},\"description\":\"pr_description\"," \
              "\"reviewers\":[],\"close_source_branch\":true}",
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json"
            }
          ).
          to_return(status: 201)
      end

      specify { expect { subject }.to_not raise_error }
    end
  end
end
