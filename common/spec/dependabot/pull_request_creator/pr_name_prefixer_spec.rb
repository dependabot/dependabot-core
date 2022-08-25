# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/pr_name_prefixer"

RSpec.describe Dependabot::PullRequestCreator::PrNamePrefixer do
  subject(:builder) do
    described_class.new(
      source: source,
      dependencies: dependencies,
      credentials: credentials,
      commit_message_options: commit_message_options,
      security_fix: security_fix
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:development_dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
      requirements: [{
        file: "Gemfile",
        requirement: "~> 1.5.0",
        groups: ["test"],
        source: nil
      }],
      previous_requirements: [{
        file: "Gemfile",
        requirement: "~> 1.4.0",
        groups: ["test"],
        source: nil
      }]
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:commit_message_options) { {} }
  let(:security_fix) { false }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  describe "#pr_name_prefix" do
    subject(:pr_name_prefix) { builder.pr_name_prefix }

    context "that doesn't use a commit convention" do
      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100").
          to_return(
            status: 200,
            body: commits_response,
            headers: json_header
          )
      end
      let(:commits_response) { fixture("github", "commits.json") }

      it { is_expected.to eq("") }

      context "but does have prefixed commits" do
        let(:commits_response) { fixture("github", "commits_prefixed.json") }

        it { is_expected.to eq("build(deps): ") }
      end

      context "that 409s when asked for commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100").
            to_return(status: 409, headers: json_header)
        end

        it { is_expected.to eq("") }
      end

      context "that 404s when asked for commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100").
            to_return(status: 404, headers: json_header)
        end

        it { is_expected.to eq("") }
      end

      context "from GitLab" do
        let(:source) do
          Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
        end
        let(:watched_repo_url) do
          "https://gitlab.com/api/v4/projects/" \
            "#{CGI.escape(source.repo)}/repository"
        end
        let(:commits_response) { fixture("gitlab", "commits.json") }
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(
              status: 200,
              body: commits_response,
              headers: json_header
            )
        end

        it { is_expected.to eq("") }
      end

      context "from Azure with no author email" do
        let(:source) do
          Dependabot::Source.new(provider: "azure",
                                 repo: "org/gocardless/_git/bump")
        end
        let(:watched_repo_url) do
          "https://dev.azure.com/org/gocardless/_apis/git/repositories/bump"
        end

        let(:commits_response) do
          fixture("azure", "commits_no_author_email.json")
        end
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(
              status: 200,
              body: commits_response,
              headers: json_header
            )
        end

        it { is_expected.to eq("") }
      end

      context "with a security vulnerability fixed" do
        let(:security_fix) { true }
        it { is_expected.to eq("[Security] ") }
      end
    end

    context "that uses angular commits" do
      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "commits_angular.json"),
                    headers: json_header)
      end

      it { is_expected.to eq("chore(deps): ") }

      context "and capitalizes them" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100").
            to_return(
              status: 200,
              body: fixture("github", "commits_angular_capitalized.json"),
              headers: json_header
            )
        end

        it { is_expected.to eq("Chore(deps): ") }
      end

      context "with a security vulnerability fixed" do
        let(:security_fix) { true }
        it { is_expected.to eq("chore(deps): [security] ") }
      end

      context "with a dev dependency" do
        let(:dependencies) { [development_dependency] }
        it { is_expected.to eq("chore(deps-dev): ") }
      end
    end

    context "that uses eslint commits" do
      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "commits_eslint.json"),
                    headers: json_header)
      end

      it { is_expected.to eq("Upgrade: ") }

      context "with a security vulnerability fixed" do
        let(:security_fix) { true }
        it { is_expected.to eq("Upgrade: [Security] ") }
      end
    end

    context "that uses gitmoji commits" do
      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "commits_gitmoji.json"),
                    headers: json_header)
      end

      it { is_expected.to eq("⬆️ ") }

      context "with a security vulnerability fixed" do
        let(:security_fix) { true }
        it { is_expected.to eq("⬆️🔒 ") }
      end
    end

    context "when commit_message_options are provided" do
      let(:commit_message_options) do
        {
          prefix: prefix,
          prefix_development: development_prefix,
          include_scope: include_scope
        }.compact
      end
      let(:prefix) { "custom" }
      let(:development_prefix) { nil }
      let(:include_scope) { nil }

      it { is_expected.to eq("custom: ") }

      context "with a security vulnerability fixed" do
        let(:security_fix) { true }
        it { is_expected.to eq("custom: [security] ") }

        context "with a capitalised prefix" do
          let(:prefix) { "Custom" }
          it { is_expected.to eq("Custom: [Security] ") }
        end
      end

      context "when asked to include the scope" do
        let(:include_scope) { true }
        it { is_expected.to eq("custom(deps): ") }
      end

      context "when asked not to include the scope" do
        let(:include_scope) { false }
        it { is_expected.to eq("custom: ") }
      end

      context "with a development prefix" do
        let(:development_prefix) { "chore" }
        it { is_expected.to eq("custom: ") }

        context "for a development dependency" do
          let(:dependencies) { [development_dependency] }
          it { is_expected.to eq("chore: ") }
        end
      end
    end
  end
end
