# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/bitbucket"

RSpec.describe Dependabot::Clients::Bitbucket do
  let(:current_user_url) { "https://api.bitbucket.org/2.0/user?fields=uuid" }
  let(:access_token) { "access_token" }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "bitbucket.org",
      "username" => nil,
      "token" => access_token
    })]
  end
  let(:branch) { "master" }
  let(:repo) { "test/repo" }
  let(:base_url) { "https://bitbucket.org/test/repo" }
  let(:api_base_url) { "https://api.bitbucket.org/2.0/repositories/" }
  let(:source) { Dependabot::Source.from_url(base_url + "/src/master/") }
  let(:client) do
    described_class.for_source(source: source, credentials: credentials)
  end

  before do
    stub_request(:get, current_user_url)
      .with(headers: { "Authorization" => "Bearer #{access_token}" })
      .to_return(status: 200, body: fixture("bitbucket", "current_user.json"))
  end

  describe "#default_reviewers" do
    subject(:default_reviewers) do
      client.default_reviewers(repo)
    end

    let(:default_reviewers_url) { api_base_url + repo + "/default-reviewers?pagelen=100&fields=values.uuid,next" }

    context "when no default reviewers are defined" do
      before do
        stub_request(:get, default_reviewers_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "default_reviewers_no_data.json"))
      end

      specify { expect { default_reviewers }.not_to raise_error }

      it { is_expected.to eq([]) }
    end

    context "when default reviewers are defined" do
      before do
        stub_request(:get, default_reviewers_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "default_reviewers_with_data.json"))
      end

      specify { expect { default_reviewers }.not_to raise_error }

      it { is_expected.to eq([{ uuid: "{00000000-0000-0000-0000-000000000001}" }]) }
    end

    context "when default reviewers are defined but access denied on current user" do
      before do
        stub_request(:get, default_reviewers_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "default_reviewers_with_data.json"))
        stub_request(:get, current_user_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 401, body: fixture("bitbucket", "current_user_no_access.json"))
      end

      specify { expect { default_reviewers }.not_to raise_error }

      it {
        expect(default_reviewers).to eq(
          [
            { uuid: "{00000000-0000-0000-0000-000000000001}" },
            { uuid: "{11111111-6349-0000-aea6-111111111111}" }
          ]
        )
      }
    end
  end

  describe "#create_pull_request" do
    subject(:create_pull_request) do
      client.create_pull_request(repo, "pr_name", "source_branch", "target_branch", "pr_description", nil)
    end

    let(:default_reviewers_url) { api_base_url + repo + "/default-reviewers?pagelen=100&fields=values.uuid,next" }
    let(:pull_request_url) { api_base_url + repo + "/pullrequests" }

    context "when a pull request created successfully" do
      before do
        stub_request(:get, default_reviewers_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 201, body: fixture("bitbucket", "default_reviewers_no_data.json"))

        stub_request(:post, pull_request_url)
          .with(
            body: "{\"title\":\"pr_name\",\"source\":{\"branch\":{\"name\":\"source_branch\"}}," \
                  "\"destination\":{\"branch\":{\"name\":\"target_branch\"}},\"description\":\"pr_description\"," \
                  "\"reviewers\":[],\"close_source_branch\":true}",
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-Type" => "application/json"
            }
          )
          .to_return(status: 201)
      end

      specify { expect { create_pull_request }.not_to raise_error }
    end
  end

  describe "#remove_current_user_from_default_reviewer" do
    subject(:current_user) do
      client.current_user
    end

    specify { expect { current_user }.not_to raise_error }

    it { is_expected.to eq("{11111111-6349-0000-aea6-111111111111}") }
  end

  describe "#pull_requests" do
    subject(:pull_requests) do
      client.pull_requests(repo, "source_branch", "target_branch")
    end

    let(:status_params) { "?status=OPEN&status=MERGED&status=DECLINED&status=SUPERSEDED" }
    let(:default_pull_requests_url) { api_base_url + repo + "/pullrequests" + status_params }

    context "when no pull requests found with matching source and target branch" do
      before do
        stub_request(:get, default_pull_requests_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "pull_requests_no_match.json"))
      end

      specify { expect { pull_requests }.not_to raise_error }

      it { is_expected.to eq([]) }
    end

    context "when pull request found with matching source and target branch" do
      before do
        stub_request(:get, default_pull_requests_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "pull_requests_with_match.json"))
      end

      specify { expect { pull_requests }.not_to raise_error }

      it {
        expect(pull_requests).to eq([
          {
            "author" => {
              "display_name" => "Author"
            },
            "description" => "Second pull request",
            "destination" => {
              "branch" => {
                "name" => "target_branch"
              }
            },
            "id" => 27,
            "source" => {
              "branch" => {
                "name" => "source_branch"
              }
            },
            "state" => "OPEN",
            "title" => "Second pull request"
          }
        ])
      }
    end

    context "when only open pull requests match source and target branch" do
      subject(:pull_requests) do
        client.pull_requests(repo, "source_branch", "target_branch", %w(OPEN))
      end

      let(:pull_requests_url) { api_base_url + repo + "/pullrequests?status=OPEN" }

      before do
        stub_request(:get, pull_requests_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "pull_requests_with_match.json"))
      end

      specify { expect { pull_requests }.not_to raise_error }

      it {
        expect(pull_requests).to eq([
          {
            "author" => {
              "display_name" => "Author"
            },
            "description" => "Second pull request",
            "destination" => {
              "branch" => {
                "name" => "target_branch"
              }
            },
            "id" => 27,
            "source" => {
              "branch" => {
                "name" => "source_branch"
              }
            },
            "state" => "OPEN",
            "title" => "Second pull request"
          }
        ])
      }
    end

    context "when open pull requests match target branch" do
      subject(:pull_requests) do
        client.pull_requests(repo, nil, "target_branch", %w(OPEN))
      end

      let(:pull_requests_url) { api_base_url + repo + "/pullrequests?status=OPEN" }

      before do
        stub_request(:get, pull_requests_url)
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(status: 200, body: fixture("bitbucket", "pull_requests_no_match.json"))
      end

      specify { expect { pull_requests }.not_to raise_error }

      it {
        expect(pull_requests).to eq([
          {
            "author" => {
              "display_name" => "Pull request Author"
            },
            "created_on" => "2021-05-17T14:52:37.237653+00:00",
            "description" => "Pull request description",
            "destination" => {
              "branch" => {
                "name" => "target_branch"
              }
            },
            "id" => 7,
            "source" => {
              "branch" => {
                "name" => "branch_1"
              }
            },
            "state" => "OPEN",
            "title" => "Pull request title",
            "updated_on" => "2021-05-17T14:52:37.237653+00:00"
          }
        ])
      }
    end
  end

  describe "#decline pull request" do
    let(:default_decline_url) { api_base_url + repo + "/pullrequests/15/decline" }
    let(:default_comment_url) { api_base_url + repo + "/pullrequests/15/comments" }

    context "with provided comment" do
      subject(:decline_pull_request) do
        client.decline_pull_request(repo, 15, "Superseded by newer version")
      end

      before do
        stub_request(:post, default_decline_url)
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Accept" => "application/json"
            }
          )
          .to_return(status: 200)

        stub_request(:post, default_comment_url)
          .with(
            body: "{\"content\":{\"raw\":\"Superseded by newer version\"}}",
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-type" => "application/json"
            }
          )
          .to_return(status: 201)
      end

      specify { expect { decline_pull_request }.not_to raise_error }
    end

    context "without provided comment" do
      subject(:decline_pull_request) do
        client.decline_pull_request(repo, 15)
      end

      before do
        stub_request(:post, default_decline_url)
          .with(
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Accept" => "application/json"
            }
          )
          .to_return(status: 200)

        stub_request(:post, default_comment_url)
          .with(
            body: "{\"content\":{\"raw\":\"Dependabot declined the pull request.\"}}",
            headers: {
              "Authorization" => "Bearer #{access_token}",
              "Content-type" => "application/json"
            }
          )
          .to_return(status: 201)
      end

      specify { expect { decline_pull_request }.not_to raise_error }
    end
  end
end
