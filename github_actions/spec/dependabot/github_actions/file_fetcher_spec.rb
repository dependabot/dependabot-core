# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GithubActions::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  it_behaves_like "a dependency file fetcher"

  context "with workflow files" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_workflows.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(
        :get,
        File.join(url, ".github/workflows/integration-workflow.yml?ref=sha")
      ).with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: workflow_file_fixture,
          headers: { "content-type" => "application/json" }
        )
      stub_request(
        :get,
        File.join(url, ".github/workflows/sherlock-workflow.yaml?ref=sha")
      ).with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: workflow_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    let(:workflow_file_fixture) do
      fixture("github", "contents_githubaction_workflow_file.json")
    end

    it "fetches the workflow files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(
          %w(.github/workflows/sherlock-workflow.yaml
             .github/workflows/integration-workflow.yml)
        )
    end

    context "when an explicit directory is given" do
      let(:directory) { "/.github/workflows" }

      it "fetches the workflow files relatively to the directory" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(sherlock-workflow.yaml integration-workflow.yml))
      end

      context "when an actions.lock is present" do
        before do
          Dependabot::Experiments.register(:github_actions_lockfile, true)
          stub_request(:get, url + ".github/workflows?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_githubaction_repo_workflows_with_lock.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + ".github/workflows/actions.lock?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_githubaction_lockfile.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the lockfile relative to the configured directory" do
          lockfile = file_fetcher_instance.files.find { |file| file.name == "actions.lock" }

          expect(lockfile&.path).to eq("/.github/workflows/actions.lock")
        end
      end
    end

    context "when an actions.lock is present" do
      before do
        Dependabot::Experiments.register(:github_actions_lockfile, true)
        # Re-stub the workflows listing to include the lockfile alongside the
        # workflow files, then stub the lockfile content fetch.
        stub_request(:get, url + ".github/workflows?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_githubaction_repo_workflows_with_lock.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, ".github/workflows/actions.lock?ref=sha")
        ).with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_githubaction_lockfile.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "additively fetches the lockfile alongside the workflow files" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(.github/workflows/sherlock-workflow.yaml
               .github/workflows/integration-workflow.yml
               .github/workflows/actions.lock)
          )
      end

      context "when a workflow uses a self repository action" do
        let(:workflow_file_fixture) do
          contents_json(".github/workflows/ci.yml", "jobs:\n  a:\n    steps:\n      - uses: $/tools/setup\n")
        end

        def contents_json(path, content)
          { type: "file", name: File.basename(path), path: path, encoding: "base64",
            content: Base64.encode64(content) }.to_json
        end

        before do
          stub_request(:get, github_url + "repos/gocardless/bump/git/trees/sha?recursive=true")
            .to_return(
              status: 200,
              headers: { "content-type" => "application/json" },
              body: { truncated: false, tree: [
                { path: "tools/setup/action.yml", type: "blob" },
                { path: ".github/actions/inner/action.yaml", type: "blob" },
                { path: "tools/setup/README.md", type: "blob" }
              ] }.to_json
            )
          %w(tools/setup/action.yml .github/actions/inner/action.yaml).each do |path|
            stub_request(:get, url + "#{path}?ref=sha")
              .to_return(status: 200,
                         body: contents_json(path, "runs: {}\n"),
                         headers: { "content-type" => "application/json" })
          end
        end

        it "fetches every action definition as a support file" do
          support = file_fetcher_instance.files.select(&:support_file?)
          expect(support.map(&:path)).to contain_exactly(
            "/tools/setup/action.yml",
            "/.github/actions/inner/action.yaml"
          )
        end

        context "with a quoted uses key" do
          let(:workflow_file_fixture) do
            contents_json(".github/workflows/ci.yml", "jobs:\n  a:\n    steps:\n      - \"uses\": \"$/tools/setup\"\n")
          end

          it "still fetches the action definitions" do
            expect(file_fetcher_instance.files.count(&:support_file?)).to eq(2)
          end
        end
      end

      context "when the experiment is disabled" do
        before { Dependabot::Experiments.reset! }

        it "keeps the existing workflow-only behavior" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(
              %w(.github/workflows/sherlock-workflow.yaml
                 .github/workflows/integration-workflow.yml)
            )
          expect(a_request(:get, url + ".github/workflows/actions.lock?ref=sha")).not_to have_been_made
        end
      end

      context "with a non-github.com source" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "ghes.other.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "gocardless/bump",
            directory: directory,
            hostname: "ghes.other.com",
            api_endpoint: github_url
          )
        end

        it "keeps the existing workflow-only behavior" do
          expect(file_fetcher_instance.files.map(&:name))
            .to match_array(
              %w(.github/workflows/sherlock-workflow.yaml
                 .github/workflows/integration-workflow.yml)
            )
          expect(a_request(:get, url + ".github/workflows/actions.lock?ref=sha")).not_to have_been_made
        end
      end

      context "with a ghe.com source" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "tenant.ghe.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "gocardless/bump",
            directory: directory,
            hostname: "tenant.ghe.com",
            api_endpoint: github_url
          )
        end

        it "fetches the lockfile" do
          expect(file_fetcher_instance.files.map(&:name)).to include(".github/workflows/actions.lock")
        end
      end
    end

    context "when it has an invalid encoding" do
      let(:workflow_file_fixture) { fixture("github", "contents_image.json") }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotParseable)
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
        ).with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: bad_workflow_file_fixture,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the first workflow file, and ignores the invalid one" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(%w(.github/workflows/integration-workflow.yml))
      end

      context "when an actions.lock is present" do
        before do
          Dependabot::Experiments.register(:github_actions_lockfile, true)
          stub_request(:get, url + ".github/workflows?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_githubaction_repo_workflows_with_lock.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "keeps the workflow-only path" do
          expect(file_fetcher_instance.files.map(&:name))
            .to contain_exactly(".github/workflows/integration-workflow.yml")
          expect(a_request(:get, url + ".github/workflows/actions.lock?ref=sha")).not_to have_been_made
        end
      end
    end

    context "with an additional composite action file" do
      let(:composite_action_file_fixture) do
        fixture("github", "contents_githubaction_composite_file.json")
      end

      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_githubaction_repo_base_composite.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(
          :get,
          File.join(url, "action.yml?ref=sha")
        ).with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: composite_action_file_fixture,
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches all action files" do
        expect(file_fetcher_instance.files.map(&:name))
          .to match_array(
            %w(action.yml
               .github/workflows/sherlock-workflow.yaml
               .github/workflows/integration-workflow.yml)
          )
      end
    end
  end

  context "with an empty workflow directory" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_basic.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: "[]",
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a repo without a .github/workflows directory" do
    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: "[]",
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a repo containing only a composite action file" do
    let(:composite_action_file_fixture) do
      fixture("github", "contents_githubaction_composite_file.json")
    end

    before do
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_composite.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + ".github/workflows?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(
        :get,
        File.join(url, "action.yml?ref=sha")
      ).with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: composite_action_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the composite action file" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(
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
      stub_request(:get, url + "action/subdir?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_githubaction_repo_base_subdir.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(
        :get,
        File.join(url, "action/subdir/action.yaml?ref=sha")
      ).with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: composite_action_file_fixture,
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the composite action file" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(
          %w(action.yaml)
        )
      expect(a_request(:get, url + "action/subdir/actions.lock?ref=sha")).not_to have_been_made
    end
  end

  context "with a composite action directory and an actions.lock" do
    let(:directory) { "/.github/actions/inner" }

    def contents_json(path, content)
      { type: "file", name: File.basename(path), path: path, encoding: "base64",
        content: Base64.encode64(content) }.to_json
    end

    def listing_json(*paths)
      paths.map { |path| { type: "file", name: File.basename(path), path: path } }.to_json
    end

    before do
      Dependabot::Experiments.register(:github_actions_lockfile, true)
      {
        ".github/actions/inner" => listing_json(".github/actions/inner/action.yml"),
        ".github/actions/inner/action.yml" =>
          contents_json(".github/actions/inner/action.yml", "runs:\n  using: composite\n"),
        ".github/workflows" => listing_json(".github/workflows/ci.yml", ".github/workflows/actions.lock"),
        ".github/workflows/ci.yml" =>
          contents_json(".github/workflows/ci.yml", "jobs:\n  a:\n    steps:\n      - uses: $/.github/actions/inner\n"),
        ".github/workflows/actions.lock" => contents_json(".github/workflows/actions.lock", "version: v0.0.3\n"),
        ".github/actions/outer/action.yml" => contents_json(".github/actions/outer/action.yml", "runs: {}\n")
      }.each do |path, body|
        stub_request(:get, url + "#{path}?ref=sha")
          .to_return(status: 200, body: body, headers: { "content-type" => "application/json" })
      end
      stub_request(:get, github_url + "repos/gocardless/bump/git/trees/sha?recursive=true")
        .to_return(
          status: 200,
          headers: { "content-type" => "application/json" },
          body: { truncated: false, tree: [
            { path: ".github/actions/inner/action.yml", type: "blob" },
            { path: ".github/actions/outer/action.yml", type: "blob" }
          ] }.to_json
        )
    end

    it "fetches the root lockfile, workflows and $/ actions without making them dependency sources" do
      files = file_fetcher_instance.files
      expect(files.map { |f| [f.path, f.support_file?] }).to contain_exactly(
        ["/.github/actions/inner/action.yml", false],
        ["/.github/workflows/actions.lock", false],
        ["/.github/workflows/ci.yml", true],
        ["/.github/actions/outer/action.yml", true]
      )
    end

    context "when the repository has no lockfile" do
      before do
        stub_request(:get, url + ".github/workflows?ref=sha")
          .to_return(
            status: 200,
            body: listing_json(".github/workflows/ci.yml"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches only the composite action" do
        expect(file_fetcher_instance.files.map(&:path)).to eq(["/.github/actions/inner/action.yml"])
      end
    end

    context "when the experiment is disabled" do
      before { Dependabot::Experiments.reset! }

      it "fetches only the composite action" do
        expect(file_fetcher_instance.files.map(&:path)).to eq(["/.github/actions/inner/action.yml"])
        expect(a_request(:get, url + ".github/workflows/actions.lock?ref=sha")).not_to have_been_made
      end
    end

    context "when a repository workflow is invalidly encoded" do
      before do
        stub_request(:get, url + ".github/workflows?ref=sha")
          .to_return(
            status: 200,
            body: listing_json(
              ".github/workflows/ci.yml", ".github/workflows/bad.yml", ".github/workflows/actions.lock"
            ),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".github/workflows/bad.yml?ref=sha")
          .to_return(
            status: 200,
            body: contents_json(".github/workflows/bad.yml", "\xFF\xFE".b),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches only the composite action" do
        expect(file_fetcher_instance.files.map(&:path)).to eq(["/.github/actions/inner/action.yml"])
      end
    end
  end
end
