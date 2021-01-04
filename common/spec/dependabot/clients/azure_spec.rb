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
    subject { client.fetch_commit(nil, branch) }

    context "when response is 200" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 200, body: fixture("azure", "master_branch.json"))
      end

      specify { expect { subject }.to_not raise_error }

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }
    end

    context "when response is 404" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::NotFound)
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
  end
end
