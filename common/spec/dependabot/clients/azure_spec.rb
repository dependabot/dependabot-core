# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/azure"

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
end
