# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/azure"
require "cgi"

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

    context "when response is 403" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 403)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Forbidden)
      end
    end

    context "when response is 401" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 400" do
      before do
        stub_request(:get, branch_url).
          with(basic_auth: [username, password]).
          to_return(status: 400)
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
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Forbidden)
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
    subject do
      client.create_pull_request("pr_name", "source_branch", "target_branch",
                                 "", [], nil)
    end

    let(:pull_request_url) { repo_url + "/pullrequests?api-version=5.0" }

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
  end
  end

  describe "#create_pull_request" do
    subject do
      client.create_pull_request("pr_name", "source_branch", "target_branch",
                                 "", [], nil)
    end

    let(:pull_request_url) { repo_url + "/pullrequests?api-version=5.0" }

    context "when response is 403 & tags creation is forbidden" do
      before do
        stub_request(:post, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(
            status: 403,
            body: { message: "TF401289" }.to_json
          )
=======
    context "when response is 403" do
      before do
        stub_request(:post, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 403)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Forbidden)
>>>>>>> upstream/main
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
  end

  describe "#pull_request" do
    subject { client.pull_request(pull_request_id) }

    let(:pull_request_id) { "1" }
    let(:pull_request_url) { base_url + "/_apis/git/pullrequests/#{pull_request_id}" }

    context "when response is 200" do
      response_body = fixture("azure", "pull_request_details.json")

      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 200, body: response_body)
      end

      specify { expect { subject }.to_not raise_error }

      it { is_expected.to eq(JSON.parse(response_body)) }
    end

    context "when response is 401" do
      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 404" do
      before do
        stub_request(:get, pull_request_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::NotFound)
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

  describe "#code_search" do
    subject(:code_search) { client.fetch_repo_paths_for_code_search(search_text, source.directory) }

    let(:source) do
      Dependabot::Source.new(provider: "azure", repo: "org/project-id/_git/repo-id", branch: "main", directory: "src")
    end
    let(:repo_name) { "repo" }
    let(:project_name) { "project" }
    let(:code_search_url) do
      "https://almsearch.dev.azure.com/" +
        source.organization + "/" + source.project +
        "/_apis/search/codesearchresults?api-version=6.0"
    end
    let(:search_text) { "package.json" }
    let(:results) do
      [{ "path" => "/src/folderA/package.json" }, { "path" => "/src/folderB/package.json" },
       { "path" => "/src/folderC/package.json" }]
    end
    let(:expected_code_paths) do
      ["/src/folderA/package.json", "/src/folderB/package.json", "/src/folderC/package.json"]
    end

    before do
      repository_details_fetch_url = source.api_endpoint +
                                     source.organization + "/" + source.project +
                                     "/_apis/git/repositories/" + source.unscoped_repo +
                                     "?api-version=6.0"
      stub_request(:get, repository_details_fetch_url).
        with(basic_auth: [username, password]).
        to_return({ status: 200, body: fixture("azure", "repository_details.json") })
    end

    context "when response code is 200" do
      context "when the API returns results in multiple pages" do
        before do
          stub_request(:post, code_search_url).
            with(basic_auth: [username,
                              password],
                 body: {
                   "searchText" => search_text,
                   "$skip" => 0,
                   "$top" => 1000,
                   "$orderBy": [
                     {
                       field: "path",
                       sortOrder: "ASC"
                     }
                   ],
                   "filters" => {
                     "Project" => [CGI.unescape(project_name)],
                     "Repository" => [CGI.unescape(repo_name)],
                     "Path" => [source.directory],
                     "Branch" => [source.branch]
                   }
                 }.to_json).
            to_return({ status: 200, body: { "count" => 1002, "results" => results[0, 2] }.to_json })

          stub_request(:post, code_search_url).
            with(basic_auth: [username,
                              password],
                 body: {
                   "searchText" => search_text,
                   "$skip" => 1000,
                   "$top" => 1000,
                   "$orderBy": [
                     {
                       field: "path",
                       sortOrder: "ASC"
                     }
                   ],
                   "filters" => {
                     "Project" => [CGI.unescape(project_name)],
                     "Repository" => [CGI.unescape(repo_name)],
                     "Path" => [source.directory],
                     "Branch" => [source.branch]
                   }
                 }.to_json).
            to_return({ status: 200, body: { "count" => 1002, "results" => results[2..-1] }.to_json })
        end

        it "calls the code search API multiple times to get fetch all results and return the code paths" do
          code_paths = code_search

          expect(WebMock).to(have_requested(:post, code_search_url).times(2))
          expect(code_paths).to eq(expected_code_paths)
        end
      end

      context "when the API returns results in single page" do
        before do
          stub_request(:post, code_search_url).
            with(basic_auth: [username,
                              password],
                 body: {
                   "searchText" => search_text,
                   "$skip" => 0,
                   "$top" => 1000,
                   "$orderBy": [
                     {
                       field: "path",
                       sortOrder: "ASC"
                     }
                   ],
                   "filters" => {
                     "Project" => [CGI.unescape(project_name)],
                     "Repository" => [CGI.unescape(repo_name)],
                     "Path" => [source.directory],
                     "Branch" => [source.branch]
                   }
                 }.to_json).
            to_return({ status: 200, body: { "count" => 3, "results" => results }.to_json })
        end

        it "calls the code search API once to get all results and return the code paths" do
          code_paths = code_search

          expect(WebMock).to(have_requested(:post, code_search_url).times(1))
          expect(code_paths).to eq(expected_code_paths)
        end
      end

      context "when the API response contains number of results = 0" do
        before do
          stub_request(:post, code_search_url).
            with(basic_auth: [username,
                              password],
                 body: {
                   "searchText" => search_text,
                   "$skip" => 0,
                   "$top" => 1000,
                   "$orderBy": [
                     {
                       field: "path",
                       sortOrder: "ASC"
                     }
                   ],
                   "filters" => {
                     "Project" => [CGI.unescape(project_name)],
                     "Repository" => [CGI.unescape(repo_name)],
                     "Path" => [source.directory],
                     "Branch" => [source.branch]
                   }
                 }.to_json).
            to_return({ status: 200, body: { "count" => 0, "results" => [] }.to_json })
        end

        it "returns an empty array of code paths" do
          code_paths = code_search

          expect(WebMock).to(have_requested(:post, code_search_url).times(1))
          expect(code_paths).to be_empty
        end
      end
    end

    context "when response is 400" do
      before do
        stub_request(:post, code_search_url).
          with(basic_auth: [username, password]).
          to_return(status: 400, body: { "message" => "Invalid Project" }.to_json)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::BadRequest, "Invalid Project")
      end
    end

    context "when response is 401" do
      before do
        stub_request(:post, code_search_url).
          with(basic_auth: [username, password]).
          to_return(status: 401)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response is 404" do
      before do
        stub_request(:post, code_search_url).
          with(basic_auth: [username, password]).
          to_return(status: 404)
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::NotFound)
      end
    end
  end

  describe "#repository_details" do
    subject(:repository_details) { client.repository_details }
    let(:source) do
      Dependabot::Source.new(provider: "azure", repo: "org/project/_git/repo", branch: "main", directory: "src")
    end

    let(:repository_details_fetch_url) do
      source.api_endpoint +
        source.organization + "/" + source.project +
        "/_apis/git/repositories/" + source.unscoped_repo +
        "?api-version=6.0"
    end

    context "when response code is 200" do
      response_body = fixture("azure", "repository_details.json")

      before do
        stub_request(:get, repository_details_fetch_url).
          with(basic_auth: [username, password]).
          to_return({ status: 200, body: response_body })
      end

      it "returns the repo details" do
        repo_details = repository_details

        # Expect
        expect(repo_details).not_to be_nil
        expect(repo_details).to eq(JSON.parse(response_body))
      end
    end

    context "when response code is 401" do
      before do
        stub_request(:get, repository_details_fetch_url).
          with(basic_auth: [username, password]).
          to_return({ status: 401 })
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::Unauthorized)
      end
    end

    context "when response code is 404" do
      before do
        stub_request(:get, repository_details_fetch_url).
          with(basic_auth: [username, password]).
          to_return({ status: 404 })
      end

      it "raises a helpful error" do
        expect { subject }.to raise_error(Dependabot::Clients::Azure::NotFound)
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
