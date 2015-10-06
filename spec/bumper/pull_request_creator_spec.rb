require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/pull_request_creator"

RSpec.describe PullRequestCreator do
  subject(:creator) do
    PullRequestCreator.new(repo: repo, dependency: dependency, files: files)
  end

  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile] }

  let(:gemfile) do
    DependencyFile.new(name: "Gemfile", content: fixture("Gemfile"))
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{repo}" }
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }

  before do
    stub_request(:get, watched_repo_url).
      to_return(status: 200,
                body: fixture("github", "bump_repo.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/git/refs/heads/master").
      to_return(status: 200,
                body: fixture("github", "ref.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/refs").
      to_return(status: 200,
                body: fixture("github", "create_ref.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/contents/#{gemfile.name}").
      to_return(status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: json_header)
    stub_request(:put, "#{watched_repo_url}/contents/#{gemfile.name}").
      to_return(status: 200,
                body: fixture("github", "update_file.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/pulls").
      to_return(status: 200,
                body: fixture("github", "create_pr.json"),
                headers: json_header)

    stub_request(:get, business_repo_url).
      to_return(status: 200,
                body: fixture("github", "business_repo.json"),
                headers: json_header)
    stub_request(:get, "#{business_repo_url}/contents/").
      to_return(status: 200,
                body: fixture("github", "business_files.json"),
                headers: json_header)
    stub_request(:get, "https://rubygems.org/api/v1/gems/business.yaml").
      to_return(status: 200, body: fixture("rubygems_response.yaml"))
  end

  describe "#create" do
    it "creates a branch with the right name" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/refs").
        with(body: {
               ref: "refs/heads/bump_business_to_1.5.0",
               sha: "aa218f56b14c9653891f9e74264a383fa43fefbd"
             })
    end

    it "pushes changes to that branch" do
      creator.create

      expect(WebMock).
        to have_requested(:put, "#{watched_repo_url}/contents/Gemfile").
        with(body: {
               branch: "bump_business_to_1.5.0",
               sha: "dbce0c9e2e7efd19139c2c0aeb0110e837812c2f",
               content: "c291cmNlICJodHRwczovL3J1YnlnZW1zLm9yZyIKCmdlbSAiYnVza"\
                        "W5lc3MiLCAifj4gMS40LjAiCmdlbSAic3RhdGVzbWFuIiwgIn4+ID"\
                        "EuMi4wIgo=",
               message: "Updating Gemfile"
             })
    end

    it "creates a PR with the right details" do
      creator.create

      repo_url = "https://api.github.com/repos/gocardless/bump"
      expect(WebMock).
        to have_requested(:post, "#{repo_url}/pulls").
        with(body: {
               base: "master",
               head: "bump_business_to_1.5.0",
               title: "Bump business to 1.5.0",
               body: "Bumps [business](#{dependency.github_repo_url}) to 1.5.0"\
                     "\n- [Changelog](#{dependency.changelog_url})"\
                     "\n- [Commits](#{dependency.github_repo_url + '/commits'})"
             })
    end

    context "when a branch for this update already exists" do
      before do
        stub_request(:post, "#{watched_repo_url}/git/refs").
          to_return(status: 422,
                    body: fixture("github", "create_ref_error.json"),
                    headers: json_header)
      end

      specify { expect { creator.create }.to_not raise_error }

      it "doesn't push changes to the branch" do
        creator.create

        expect(WebMock).
          to_not have_requested(:put, "#{watched_repo_url}/contents/Gemfile")
      end

      it "doesn't try to re-create the PR" do
        creator.create
        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/pulls")
      end
    end
  end
end
