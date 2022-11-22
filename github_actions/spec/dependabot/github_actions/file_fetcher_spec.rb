# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GithubActions::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with workflow files" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_workflows.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(
        :get,
        File.join(url, ".github/workflows/integration-workflow.yml?ref=sha")
      ).with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: workflow_file_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(
        :get,
        File.join(url, ".github/workflows/sherlock-workflow.yaml?ref=sha")
      ).with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: workflow_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:workflow_file_fixture) do
      fixture("github", "contents_githubaction_workflow_file.json")
    end

    it "fetches the workflow files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(.github/workflows/sherlock-workflow.yaml
             .github/workflows/integration-workflow.yml)
        )
    end

    context "and an explicit directory given" do
      let(:directory) { "/.github/workflows" }

      it "fetches the workflow files relatively to the directory" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(sherlock-workflow.yaml integration-workflow.yml))
      end
    end

    context "that has an invalid encoding" do
      let(:workflow_file_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when only one file has an invalid encoding" do
      let(:bad_workflow_file_fixture) do
        fixture("github", "contents_image.json")
      end

      before do
        stub_request(
          :get,
          File.join(url, ".github/workflows/sherlock-workflow.yaml?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: bad_workflow_file_fixture,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the first workflow file, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(.github/workflows/integration-workflow.yml))
      end
    end

    context "with an additional composite action file" do
      let(:composite_action_file_fixture) do
        fixture("github", "contents_githubaction_composite_file.json")
      end

      before do
        stub_request(:get, url + "?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_githubaction_repo_base_composite.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(
          :get,
          File.join(url, "action.yml?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: composite_action_file_fixture,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches all action files" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(action.yml
               .github/workflows/sherlock-workflow.yaml
               .github/workflows/integration-workflow.yml)
          )
      end
    end
  end

  context "with an empty workflow directory" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: "[]",
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a repo without a .github/workflows directory" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: "[]",
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a repo containg only a composite action file" do
    let(:composite_action_file_fixture) do
      fixture("github", "contents_githubaction_composite_file.json")
    end

    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_composite.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(
        :get,
        File.join(url, "action.yml?ref=sha")
      ).with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: composite_action_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the composite action file" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(action.yml)
        )
    end
  end

  context "with a repo containing a composite action file in a subdirectory" do
    let(:composite_action_file_fixture) do
      fixture("github", "contents_githubaction_composite_file.json")
    end
    let(:directory) { "action/subdir" }

    before do
      stub_request(:get, url + "action/subdir?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_subdir.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(
        :get,
        File.join(url, "action/subdir/action.yaml?ref=sha")
      ).with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: composite_action_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the composite action file" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(action.yaml)
        )
    end
  end
end
