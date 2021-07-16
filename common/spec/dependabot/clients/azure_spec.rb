# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/azure"

RSpec.shared_examples "#get using auth headers" do |credential|
  before do
    stub_request(:get, base_url).
      with(headers: credential["headers"]).
      to_return(status: 200, body: '{"result": "Success"}')
  end

  it "Using #{credential['token_type']} token in credentials" do
    client = described_class.for_source(
      source: source,
      credentials: credential["credentials"]
    )
    response = JSON.parse(client.get(base_url).body)
    expect(response["result"]).to eq("Success")
  end
end

RSpec.describe Dependabot::Clients::Azure do
  let(:username) { "username" }
  let(:password) { "password" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "dev.azure.com",
      "username" => username,
      "password" => password
    }]
  end
  let(:branch) { "master" }
  let(:base_url) { "https://dev.azure.com/org/gocardless" }
  let(:repo_url) { base_url + "/_apis/git/repositories/gocardless" }
  let(:branch_url) { repo_url + "/stats/branches?name=" + branch }
  let(:source) { Dependabot::Source.from_url(base_url + "/_git/gocardless") }
  let(:client) do
    described_class.for_source(source: source, credentials: credentials)
  end

  describe "#fetch_commit" do
    subject(:fetch_commit) { client.fetch_commit(nil, branch) }

    context "when response is 200" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 200, body: fixture("azure", "master_branch.json"))
      end

      specify { expect { fetch_commit }.to_not raise_error }

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }
    end

    context "when response is 404" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { fetch_commit }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end

    context "when response is 403" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 403)
      end

      it "raises a helpful error" do
        expect { fetch_commit }.to raise_error(Dependabot::Clients::Azure::Forbidden)
      end
    end

    context "when response is 401" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { fetch_commit }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 400" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 400)
      end

      it "raises a helpful error" do
        expect { fetch_commit }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end

  describe "#create_commit" do
    subject(:create_commit) do
      client.create_commit(
        "master",
        "base-sha",
        "Commit message",
        [],
        author_details
      )
    end

    let(:commit_url) { repo_url + "/pushes?api-version=5.0" }

    context "when response is 403" do
      let(:author_details) do
        { email: "support@dependabot.com", name: "dependabot" }
      end

      before do
        stub_request(:post, commit_url).
          with(basic_auth: [username, password]).
          to_return(status: 403)
      end

      it "raises a helpful error" do
        expect { create_commit }.to raise_error(Dependabot::Clients::Azure::Forbidden)
      end
    end

    context "when response is 200" do
      before do
        stub_request(:post, commit_url).
          with(basic_auth: [username, password]).
          to_return(status: 200)
      end

      context "when author_details is nil" do
        let(:author_details) { nil }
        it "pushes commit without author property" do
          create_commit

          expect(WebMock).
            to(
              have_requested(:post, "#{repo_url}/pushes?api-version=5.0").
                with do |req|
                  json_body = JSON.parse(req.body)
                  expect(json_body.fetch("commits").count).to eq(1)
                  expect(json_body.fetch("commits").first.keys).
                    to_not include("author")
                end
            )
        end
      end

      context "when author_details contains name and email" do
        let(:author_details) do
          { email: "support@dependabot.com", name: "dependabot" }
        end

        it "pushes commit with author property containing name and email" do
          create_commit

          expect(WebMock).
            to(
              have_requested(:post, "#{repo_url}/pushes?api-version=5.0").
                with do |req|
                  json_body = JSON.parse(req.body)
                  expect(json_body.fetch("commits").count).to eq(1)
                  expect(json_body.fetch("commits").first.fetch("author")).
                    to eq(author_details.transform_keys(&:to_s))
                end
            )
        end
      end
    end
  end

  describe "#create_pull_request" do
    subject(:create_pull_request) do
      client.create_pull_request(
        pr_name, source_branch, target_branch,
        pr_description, labels, reviewers, work_item
      )
    end

    let(:pr_name) { "test-create-pr" }
    let(:source_branch) { "feature/test-create-pr" }
    let(:target_branch) { "main" }
    let(:pr_description) { "PR description" }
    let(:labels) { [] }
    let(:reviewers) { [] }
    let(:work_item) { nil }
    let(:create_pull_request_url) { repo_url + "/pullrequests?api-version=5.0" }

    context "when response is 200" do
      response_body = fixture("azure", "create_pull_request_details.json")

      before do
        request_body = {
          sourceRefName: "refs/heads/#{source_branch}",
          targetRefName: "refs/heads/#{target_branch}", title: pr_name,
          description: pr_description, labels: [], workItemRefs: [], reviewers: []
        }

        stub_request(:post, create_pull_request_url).
          with(basic_auth: [username, password], body: JSON.dump(request_body)).
          to_return(status: 200, body: response_body)
      end

      it "returns the parsed response" do
        expect(create_pull_request).to eq(JSON.parse(response_body))
      end
    end

    context "when response is 200 - with workItem" do
      let(:work_item) { 42 }
      response_body = fixture("azure", "create_pull_request_details.json")

      before do
        request_body = {
          sourceRefName: "refs/heads/#{source_branch}",
          targetRefName: "refs/heads/#{target_branch}", title: pr_name,
          description: pr_description, labels: [], workItemRefs: [{ id: 42 }], reviewers: []
        }

        stub_request(:post, create_pull_request_url).
          with(basic_auth: [username, password], body: JSON.dump(request_body)).
          to_return(status: 200, body: response_body)
      end

      it "returns the parsed response" do
        expect(create_pull_request).to eq(JSON.parse(response_body))
      end
    end

    context "when response is 200 - with reviewer" do
      let(:reviewers) { ["d6245f20-2af8-44f4-9451-8107cb2767db"] }
      response_body = fixture("azure", "create_pull_request_details.json")

      before do
        request_body = {
          sourceRefName: "refs/heads/#{source_branch}",
          targetRefName: "refs/heads/#{target_branch}", title: pr_name,
          description: pr_description, labels: [], workItemRefs: [],
          reviewers: [{ id: "d6245f20-2af8-44f4-9451-8107cb2767db" }]
        }

        stub_request(:post, create_pull_request_url).
          with(basic_auth: [username, password], body: JSON.dump(request_body)).
          to_return(status: 200, body: response_body)
      end

      specify { expect { create_pull_request }.to_not raise_error }

      it "returns the parsed response" do
        expect(create_pull_request).to eq(JSON.parse(response_body))
      end
    end

    context "when response is 401" do
      before do
        stub_request(:post, create_pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { create_pull_request }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 403 & tags creation is forbidden" do
      before do
        stub_request(:post, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(
            status: 403,
            body: { message: "TF401289" }.to_json
          )
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::TagsCreationForbidden)
      end
    end

    context "when response is 403" do
      before do
        stub_request(:post, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 403)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Forbidden)
      end
    end

    context "when response is 404" do
      before do
        stub_request(:post, create_pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { create_pull_request }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end

  describe "#autocomplete_pull_request" do
    subject(:autocomplete_pull_request) do
      client.autocomplete_pull_request(
        pull_request_id, auto_complete_set_by, merge_commit_message,
        delete_source_branch, squash_merge, merge_strategy,
        trans_work_items
      )
    end

    let(:auto_complete_set_by) { "d6245f20-2af8-44f4-9451-8107cb2767db" }
    let(:merge_commit_message) { "Dependabot merge" }
    let(:delete_source_branch) { true }
    let(:squash_merge) { true }
    let(:merge_strategy) { "squash" }
    let(:trans_work_items) { true }
    let(:pull_request_id) { 42 }
    let(:autocomplete_pull_request_url) do
      base_url + "/_apis/git/repositories/#{source.unscoped_repo}/pullrequests/42?api-version=5.1"
    end

    context "when response is 200" do
      response_body = fixture("azure", "update_pull_request_details.json")

      before do
        request_body = {
          autoCompleteSetBy: { id: "d6245f20-2af8-44f4-9451-8107cb2767db" },
          completionOptions: {
            mergeCommitMessage: "Dependabot merge", deleteSourceBranch: true,
            squashMerge: true, mergeStrategy: "squash", transitionWorkItems: true,
            autoCompleteIgnoreConfigIds: []
          }
        }

        stub_request(:patch, autocomplete_pull_request_url).
          with(basic_auth: [username, password], body: JSON.dump(request_body)).
          to_return(status: 200, body: response_body)
      end

      specify { expect { autocomplete_pull_request }.to_not raise_error }

      it { is_expected.to eq(JSON.parse(response_body)) }
    end

    context "when response is 401" do
      before do
        stub_request(:patch, autocomplete_pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { autocomplete_pull_request }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 404" do
      before do
        stub_request(:patch, autocomplete_pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { autocomplete_pull_request }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end

  describe "#pull_request" do
    subject(:pull_request) { client.pull_request(pull_request_id) }

    let(:pull_request_id) { "1" }
    let(:pull_request_url) { base_url + "/_apis/git/pullrequests/#{pull_request_id}" }

    context "when response is 200" do
      response_body = fixture("azure", "pull_request_details.json")

      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 200, body: response_body)
      end

      specify { expect { pull_request }.to_not raise_error }

      it { is_expected.to eq(JSON.parse(response_body)) }
    end

    context "when response is 401" do
      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { pull_request }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 404" do
      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { pull_request }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end

  describe "#update_ref" do
    subject(:update_ref) do
      client.update_ref(
        branch,
        old_commit_id,
        new_commit_id
      )
    end

    let(:old_commit_id) { "oldcommitsha" }
    let(:new_commit_id) { "newcommitsha" }
    let(:update_ref_url) { repo_url + "/refs?api-version=5.0" }

    it "sends update branch request with old and new commit id" do
      stub_request(:post, update_ref_url).
        with(basic_auth: [username, password]).
        to_return(status: 200, body: fixture("azure", "update_ref.json"))

      update_ref

      expect(WebMock).
        to(
          have_requested(:post, update_ref_url).
            with do |req|
              json_body = JSON.parse(req.body)
              expect(json_body.count).to eq(1)
              ref_update_details = json_body.first
              expect(ref_update_details.fetch("name")).
                to eq("refs/heads/#{branch}")
              expect(ref_update_details.fetch("oldObjectId")).
                to eq(old_commit_id)
              expect(ref_update_details.fetch("newObjectId")).
                to eq(new_commit_id)
            end
        )
    end
  end

  describe "#get" do
    context "Using auth headers" do
      token = ":test_token"
      encoded_token = Base64.encode64(":test_token").delete("\n")
      bearer_token = "test_token"
      basic_non_encoded_token_data =
        {
          "token_type" => "basic non encoded",
          "credentials" => [
            {
              "type" => "git_source",
              "host" => "dev.azure.com",
              "token" => token
            }
          ],
          "headers" => { "Authorization" => "Basic #{encoded_token}" }
        }
      basic_encoded_token_data =
        {
          "token_type" => "basic encoded",
          "credentials" => [
            {
              "type" => "git_source",
              "host" => "dev.azure.com",
              "token" => encoded_token.to_s
            }
          ],
          "headers" => { "Authorization" => "Basic #{encoded_token}" }
        }
      bearer_token_data =
        {
          "token_type" => "bearer",
          "credentials" => [
            {
              "type" => "git_source",
              "host" => "dev.azure.com",
              "token" => bearer_token
            }
          ],
          "headers" => { "Authorization" => "Bearer #{bearer_token}" }
        }

      include_examples "#get using auth headers", basic_non_encoded_token_data
      include_examples "#get using auth headers", basic_encoded_token_data
      include_examples "#get using auth headers", bearer_token_data
    end

    context "Retries" do
      context "for GET" do
        it "with failure count <= max_retries" do
          # Request succeeds (200) on second attempt.
          stub_request(:get, base_url).
            with(basic_auth: [username, password]).
            to_return({ status: 502 }, { status: 200 })

          response = client.get(base_url)
          expect(response.status).to eq(200)
        end

        it "with failure count > max_retries raises error" do
          #  Request fails (503) multiple times and exceeds max_retry limit
          stub_request(:get, base_url).
            with(basic_auth: [username, password]).
            to_return({ status: 503 }, { status: 503 }, { status: 503 })

          expect { client.get(base_url) }.to raise_error(Dependabot::Clients::Azure::ServiceNotAvailable)
        end
      end

      context "for POST" do
        before :each do
          @request_body = "request body"
        end
        it "with failure count <= max_retries" do
          # Request succeeds on thrid attempt
          stub_request(:post, base_url).
            with(basic_auth: [username, password], body: @request_body).
            to_return({ status: 503 }, { status: 503 }, { status: 200 })

          response = client.post(base_url, @request_body)
          expect(response.status).to eq(200)
        end

        it "with failure count > max_retries raises an error" do
          stub_request(:post, base_url).
            with(basic_auth: [username, password], body: @request_body).
            to_return({ status: 503 }, { status: 503 }, { status: 503 }, { status: 503 })

          expect { client.post(base_url, @request_body) }.
            to raise_error(Dependabot::Clients::Azure::ServiceNotAvailable)
        end
      end
    end
  end
end
