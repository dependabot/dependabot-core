# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/metadata_finders/base/changelog_finder"

RSpec.describe Dependabot::MetadataFinders::Base::ChangelogFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      credentials: credentials,
      dependency: dependency
    )
  end
  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      previous_requirements: dependency_previous_requirements,
      previous_version: dependency_previous_version,
      package_manager: package_manager
    )
  end
  let(:package_manager) { "bundler" }
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_version) { "1.0.0" }

  let(:dummy_commits_finder) do
    instance_double(Dependabot::MetadataFinders::Base::CommitsFinder)
  end
  before do
    allow(Dependabot::MetadataFinders::Base::CommitsFinder).
      to receive(:new).and_return(dummy_commits_finder)
    allow(dummy_commits_finder).to receive(:new_tag).and_return("v1.4.0")
  end

  shared_context "with multiple git sources" do
    let(:package_manager) { "github_actions" }
    let(:dependency_name) { "actions/checkout" }
    let(:dependency_version) { "aabbfeb2ce60b5bd82389903509092c4648a9713" }
    let(:dependency_previous_version) { nil }
    let(:dependency_requirements) do
      [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        metadata: { declaration_string: "actions/checkout@v2.1.0" },
        source: {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "v2.2.0",
          branch: nil
        }
      }, {
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        metadata: { declaration_string: "actions/checkout@master" },
        source: {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "v2.2.0",
          branch: nil
        }
      }]
    end
    let(:dependency_previous_requirements) do
      [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        metadata: { declaration_string: "actions/checkout@v2.1.0" },
        source: {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "v2.1.0",
          branch: nil
        }
      }, {
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        metadata: { declaration_string: "actions/checkout@master" },
        source: {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "master",
          branch: nil
        }
      }]
    end
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "actions/checkout"
      )
    end
    let(:github_response) { nil }
  end

  describe "#changelog_url" do
    subject { finder.changelog_url }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_url + "CHANGELOG.md?ref=master").
          to_return(status: github_status,
                    body: changelog_body,
                    headers: { "Content-Type" => "application/json" })
      end
      let(:changelog_body) { fixture("github", "changelog_contents.json") }

      context "with a changelog" do
        let(:github_response) { fixture("github", "business_files.json") }

        it "gets the right URL" do
          expect(subject).
            to eq(
              "https://github.com/gocardless/business/blob/master/CHANGELOG.md"
            )
        end

        it "caches the call to GitHub" do
          finder.changelog_url
          finder.changelog_url
          expect(WebMock).to have_requested(:get, github_url).once
        end

        context "when given a suggested_changelog_url" do
          let(:finder) do
            described_class.new(
              source: source,
              credentials: credentials,
              dependency: dependency,
              suggested_changelog_url: suggested_changelog_url
            )
          end
          let(:suggested_changelog_url) do
            "github.com/mperham/sidekiq/blob/master/Pro-Changes.md"
          end

          before do
            suggested_github_response =
              fixture("github", "contents_sidekiq.json")
            suggested_github_url =
              "https://api.github.com/repos/mperham/sidekiq/contents/"
            stub_request(:get, suggested_github_url).
              to_return(status: 200,
                        body: suggested_github_response,
                        headers: { "Content-Type" => "application/json" })
          end

          it "gets the right URL" do
            expect(subject).
              to eq(
                "https://github.com/mperham/sidekiq/blob/master/Pro-Changes.md"
              )
          end

          context "that can't be found" do
            before do
              suggested_github_url =
                "https://api.github.com/repos/mperham/sidekiq/contents/"
              stub_request(:get, suggested_github_url).
                to_return(status: 404)
            end

            it "falls back to looking for the changelog as usual" do
              expect(subject).
                to eq(
                  "https://github.com/gocardless/business/" \
                  "blob/master/CHANGELOG.md"
                )
            end
          end
        end
      end

      context "without a changelog" do
        let(:github_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        before do
          stub_request(:get, github_url + "?ref=v1.4.0").
            to_return(status: github_status,
                      body: github_response,
                      headers: { "Content-Type" => "application/json" })
        end

        it { is_expected.to be_nil }

        context "but with a changelog on the tag" do
          before do
            stub_request(:get, github_url + "?ref=v1.4.0").
              to_return(status: github_status,
                        body: fixture("github", "business_files_v1.4.0.json"),
                        headers: { "Content-Type" => "application/json" })
            stub_request(:get, github_url + "CHANGELOG.md?ref=v1.4.0").
              to_return(
                status: github_status,
                body: fixture("github", "changelog_contents.json"),
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "gets the right URL" do
            expect(subject).
              to eq(
                "https://github.com/gocardless/business/blob/v1.4.0/" \
                "CHANGELOG.md"
              )
          end
        end
      end

      context "with a docs folder" do
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "scrapy/#{dependency_name}"
          )
        end
        let(:dependency_name) { "scrapy" }
        let(:github_response) { fixture("github", "scrapy_files.json") }
        before do
          stub_request(:get, github_url + "docs").
            to_return(status: github_status,
                      body: fixture("github", "scrapy_docs_files.json"),
                      headers: { "Content-Type" => "application/json" })
        end

        context "when the file in docs mentions the version" do
          let(:changelog_body) { fixture("github", "changelog_contents.json") }
          let(:changelog_body_without_version) do
            fixture("github", "changelog_contents_japanese.json")
          end
          let(:github_url) do
            "https://api.github.com/repos/scrapy/scrapy/contents/"
          end

          before do
            stub_request(:get, github_url + "NEWS?ref=master").
              to_return(status: github_status,
                        body: changelog_body_without_version,
                        headers: { "Content-Type" => "application/json" })
            stub_request(:get, github_url + "docs/news.rst?ref=master").
              to_return(status: github_status,
                        body: changelog_body,
                        headers: { "Content-Type" => "application/json" })
          end

          it "gets the right URL" do
            expect(subject).to eq(
              "https://github.com/scrapy/scrapy/blob/master/docs/news.rst"
            )
          end

          it "caches the call to GitHub" do
            finder.changelog_url
            finder.changelog_url
            expect(WebMock).to have_requested(:get, github_url).once
          end

          context "when the first file does not have a valid encoding" do
            let(:changelog_body_without_version) do
              fixture("github", "contents_image.json")
            end

            it "gets the right URL" do
              expect(subject).to eq(
                "https://github.com/scrapy/scrapy/blob/master/docs/news.rst"
              )
            end
          end
        end
      end

      context "with a directory" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "gocardless/#{dependency_name}",
            directory: "packages/stryker"
          )
        end
        let(:changelog_body) { fixture("github", "changelog_contents.json") }
        let(:changelog_body_without_version) do
          fixture("github", "changelog_contents_japanese.json")
        end
        before do
          stub_request(:get, github_url + "packages/stryker").
            to_return(status: github_status,
                      body: fixture("github", "business_module_files.json"),
                      headers: { "Content-Type" => "application/json" })
          stub_request(:get, github_url + "CHANGELOG.md?ref=master").
            to_return(status: github_status,
                      body: changelog_body_without_version,
                      headers: { "Content-Type" => "application/json" })
          stub_request(:get, github_url + "module/CHANGELOG.md?ref=master").
            to_return(status: github_status,
                      body: changelog_body,
                      headers: { "Content-Type" => "application/json" })
        end

        it "gets the right URL" do
          expect(subject).
            to eq("https://github.com/gocardless/business/blob/master/module" \
                  "/CHANGELOG.md")
        end

        it "caches the call to GitHub" do
          finder.changelog_url
          finder.changelog_url
          expect(WebMock).to have_requested(:get, github_url).once
        end

        context "that isn't a directory" do
          before do
            stub_request(:get, github_url + "packages/stryker").
              to_return(status: github_status,
                        body: fixture("github", "changelog_contents.json"),
                        headers: { "Content-Type" => "application/json" })
            stub_request(:get, github_url).
              to_return(status: github_status,
                        body: fixture("github", "business_files.json"),
                        headers: { "Content-Type" => "application/json" })
            stub_request(:get, github_url + "CHANGELOG.md?ref=master").
              to_return(status: github_status,
                        body: changelog_body,
                        headers: { "Content-Type" => "application/json" })
          end

          it "gets the right URL" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master" \
                    "/CHANGELOG.md")
          end
        end
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        before do
          stub_request(:get, github_url + "?ref=v1.4.0").
            to_return(status: github_status,
                      body: github_response,
                      headers: { "Content-Type" => "application/json" })
        end

        it { is_expected.to be_nil }
      end

      context "without credentials" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "bitbucket.org",
            "username" => "greysteil",
            "password" => "secret_token"
          }]
        end

        context "when authentication fails" do
          before do
            stub_request(:get, github_url).to_return(status: 404)
            stub_request(:get, github_url + "?ref=v1.4.0").
              to_return(status: 404)
          end

          it { is_expected.to be_nil }
        end

        context "when authentication succeeds" do
          before do
            stub_request(:get, github_url).
              to_return(status: github_status,
                        body: github_response,
                        headers: { "Content-Type" => "application/json" })
            stub_request(:get, github_url + "CHANGELOG.md?ref=master").
              to_return(status: github_status,
                        body: changelog_body,
                        headers: { "Content-Type" => "application/json" })
          end
          let(:changelog_body) { fixture("github", "changelog_contents.json") }

          it "gets the right URL" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/" \
                    "CHANGELOG.md")
          end
        end
      end

      context "for a git dependency with multiple sources", :vcr do
        include_context "with multiple git sources"

        before do
          allow(dummy_commits_finder).to receive(:new_tag).and_return("2.2.0")
        end

        it "finds the changelog" do
          is_expected.to eq(
            "https://github.com/actions/checkout/blob/master/CHANGELOG.md"
          )
        end
      end

      context "for a git dependency" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:dependency_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: new_ref
            }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: old_ref
            }
          }]
        end
        let(:new_ref) { "master" }
        let(:old_ref) { "master" }

        it { is_expected.to be_nil }

        context "when the package manager is composer" do
          let(:package_manager) { "composer" }

          it "finds the changelog as normal" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/" \
                    "CHANGELOG.md")
          end
        end

        context "when the ref has changed" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "finds the changelog as normal" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/" \
                    "CHANGELOG.md")
          end
        end
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end
      let(:gitlab_raw_changelog_url) do
        "https://gitlab.com/org/business/raw/master/CHANGELOG.md"
      end
      let(:gitlab_repo_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_files.json") }
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, gitlab_url).
          to_return(status: gitlab_status,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, gitlab_repo_url).
          to_return(status: 200,
                    body: fixture("gitlab", "bump_repo.json"),
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, gitlab_raw_changelog_url).
          to_return(status: 200,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://gitlab.com/org/business/blob/master/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:gitlab_status) { 404 }
        let(:gitlab_response) { fixture("gitlab", "not_found.json") }
        it { is_expected.to be_nil }
      end
    end

    context "with an azure source" do
      let(:azure_repo_url) do
        "https://dev.azure.com/contoso/MyProject/_apis/git/repositories/business/items?path=/"
      end
      let(:azure_repo_contents_tree_url) do
        "https://dev.azure.com/contoso/MyProject/_apis/git/repositories/business/items?path=/" \
          "&versionDescriptor.version=sha&versionDescriptor.versionType=commit"
      end
      let(:azure_repo_contents_url) do
        "https://dev.azure.com/contoso/MyProject/_apis/git/repositories/business/trees" \
          "/9fea8a9fd1877daecde8f80137f9dfee6ec0b01a?recursive=false"
      end
      let(:azure_raw_changelog_url) do
        "https://dev.azure.com/org/8929b42a-8f67-4075-bdb1-908ea8ebfb3a/_apis/git/repositories/" \
          "3c492e10-aa73-4855-b11e-5d6d9bd7d03a/blobs/8b23cf04122670142ba2e64c7b3293f82409726a"
      end

      let(:azure_status) { 200 }
      let(:azure_response) { fixture("azure", "business_files.json") }
      let(:source) do
        Dependabot::Source.new(
          provider: "azure",
          repo: "contoso/MyProject/_git/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, azure_repo_url).
          to_return(status: azure_status,
                    body: fixture("azure", "business_folder.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, azure_repo_contents_tree_url).
          to_return(status: azure_status,
                    body: fixture("azure", "business_folder.json"),
                    headers: { "content-type" => "text/plain" })
        stub_request(:get, azure_repo_contents_url).
          to_return(status: azure_status,
                    body: fixture("azure", "business_files.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, azure_raw_changelog_url).
          to_return(status: azure_status,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      context "with credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "git_source",
            "host" => "dev.azure.com",
            "username" => "greysteil",
            "password" => "secret_token"
          }]
        end

        it "uses the credentials" do
          finder.changelog_url
          expect(WebMock).
            to have_requested(:get, azure_repo_url).
            with(basic_auth: %w(greysteil secret_token))
        end
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://dev.azure.com/contoso/MyProject/_git/business?path=/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:azure_status) { 404 }
        it { is_expected.to be_nil }
      end

      context "that is private" do
        let(:azure_status) { 403 }
        it { is_expected.to be_nil }
      end
    end

    context "with a bitbucket source" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/src" \
          "?pagelen=100"
      end
      let(:bitbucket_repo_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business"
      end
      let(:bitbucket_raw_changelog_url) do
        "https://bitbucket.org/org/business/raw/default/CHANGELOG.md"
      end

      let(:bitbucket_status) { 200 }
      let(:bitbucket_response) { fixture("bitbucket", "business_files.json") }
      let(:source) do
        Dependabot::Source.new(
          provider: "bitbucket",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, bitbucket_url).
          to_return(status: bitbucket_status,
                    body: bitbucket_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, bitbucket_repo_url).
          to_return(status: 200,
                    body: fixture("bitbucket", "bump_repo.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, bitbucket_raw_changelog_url).
          to_return(status: 200,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      context "with credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "git_source",
            "host" => "bitbucket.org",
            "username" => "greysteil",
            "password" => "secret_token"
          }]
        end

        it "uses the credentials" do
          finder.changelog_url
          expect(WebMock).
            to have_requested(:get, bitbucket_url).
            with(basic_auth: %w(greysteil secret_token))
        end
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://bitbucket.org/org/business/src/default/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:bitbucket_status) { 404 }
        it { is_expected.to be_nil }
      end

      context "that is private" do
        let(:bitbucket_status) { 403 }
        it { is_expected.to be_nil }
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }

      context "for a docker dependency" do
        let(:dependency_requirements) do
          [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { tag: "my_tag" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { tag: "my_tag" }
          }]
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#changelog_text" do
    subject(:changelog_text) { finder.changelog_text }
    let(:dependency_version) { "1.4.0" }
    let(:dependency_previous_version) { "1.0.0" }

    let(:expected_pruned_changelog) do
      "## 1.4.0 - December 24, 2014\n\n" \
        "- Add support for custom calendar load paths\n" \
        "- Remove the 'sepa' calendar\n\n\n" \
        "## 1.3.0 - December 2, 2014\n\n" \
        "- Add `Calendar#previous_business_day`\n\n\n" \
        "## 1.2.0 - November 15, 2014\n\n" \
        "- Add TARGET calendar\n\n\n" \
        "## 1.1.0 - September 30, 2014\n\n" \
        "- Add 2015 holiday definitions"
    end

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end
      let(:github_changelog_url) do
        "https://api.github.com/repos/gocardless/business/contents/" \
          "CHANGELOG.md?ref=master"
      end
      let(:github_contents_response) do
        fixture("github", "business_files.json")
      end
      let(:changelog_body) { fixture("github", "changelog_contents.json") }

      before do
        stub_request(:get, github_url).
          to_return(status: 200,
                    body: github_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_changelog_url).
          to_return(status: 200,
                    body: changelog_body,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_url + "?ref=v1.4.0").
          to_return(status: 200,
                    body: github_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_url + "CHANGELOG.md?ref=v1.4.0").
          to_return(status: 200,
                    body: changelog_body,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with a changelog" do
        let(:github_contents_response) do
          fixture("github", "business_files.json")
        end

        it { is_expected.to eq(expected_pruned_changelog) }

        it "caches the call to GitHub" do
          finder.changelog_text
          finder.changelog_text
          expect(WebMock).to have_requested(:get, github_url).once
          expect(WebMock).to have_requested(:get, github_changelog_url).once
        end

        context "that has non-standard characters" do
          let(:changelog_body) do
            fixture("github", "changelog_contents_japanese.json")
          end
          let(:dependency_version) { "0.0.6" }

          it { is_expected.to start_with("!! 0.0.5から0.0.6の変更点:") }
        end

        context "that is an image" do
          let(:changelog_body) { fixture("github", "contents_image.json") }
          it { is_expected.to be_nil }
        end

        context "for a git dependency" do
          let(:dependency_requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: new_ref
              }
            }]
          end
          let(:dependency_previous_requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: old_ref
              }
            }]
          end
          let(:new_ref) { "master" }
          let(:old_ref) { "master" }
          let(:dependency_version) { "aa12b317" }
          let(:dependency_previous_version) { "a1a123b1" }

          it { is_expected.to be_nil }

          context "when the ref has changed" do
            let(:new_ref) { "v1.4.0" }
            let(:old_ref) { "v1.0.0" }

            it { is_expected.to eq(expected_pruned_changelog) }
          end
        end

        context "for a git dependency with multiple sources", :vcr do
          include_context "with multiple git sources"

          let(:expected_pruned_changelog) do
            "## v2.2.0\n" \
              "- [Fetch all history for all tags and branches when " \
              "fetch-depth=0](https://github.com/actions/checkout/pull/258)\n" \
          end

          context "when there's a new ref" do
            it { is_expected.to start_with(expected_pruned_changelog) }
          end
        end

        context "that uses restructured text format" do
          let(:github_contents_response) do
            fixture("github", "scrapy_docs_files.json")
          end
          let(:github_changelog_url) do
            "https://api.github.com/repos/scrapy/scrapy/contents/docs/" \
              "news.rst?ref=master"
          end
          let(:changelog_body) do
            fixture("github", "changelog_contents_rst.json")
          end
          let(:dependency_version) { "1.16.0" }
          let(:dependency_previous_version) { "1.15.1" }

          let(:unconverted_text) do
            "1.16.0 (2019-02-12)\n" \
              "-------------------\n" \
              "\n" \
              "* ``pytest-selenium`` now requires pytest 3.6 or later.\n" \
              "* Fixed `issue <https://github.com/pytest-dev/" \
              "pytest-selenium/issues/216>`_ with TestingBot local tunnel."
          end

          it "does not convert the rst" do
            expect(changelog_text).to eq(unconverted_text)
          end
        end
      end

      context "without a changelog" do
        let(:github_contents_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }
      end

      context "when given a suggested_changelog_url" do
        let(:finder) do
          described_class.new(
            source: nil,
            credentials: credentials,
            dependency: dependency,
            suggested_changelog_url: suggested_changelog_url
          )
        end
        let(:suggested_changelog_url) do
          "github.com/mperham/sidekiq/blob/master/Pro-Changes.md"
        end

        before do
          suggested_github_response =
            fixture("github", "contents_sidekiq.json")
          suggested_github_url =
            "https://api.github.com/repos/mperham/sidekiq/contents/"
          stub_request(:get, suggested_github_url).
            to_return(status: 200,
                      body: suggested_github_response,
                      headers: { "Content-Type" => "application/json" })
        end

        let(:github_contents_response) do
          fixture("github", "business_files.json")
        end

        let(:github_changelog_url) do
          "https://api.github.com/repos/mperham/sidekiq/contents/" \
            "Pro-Changes.md?ref=master"
        end

        it { is_expected.to eq(expected_pruned_changelog) }
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end
      let(:gitlab_raw_changelog_url) do
        "https://gitlab.com/org/business/raw/master/CHANGELOG.md"
      end
      let(:gitlab_repo_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness"
      end

      let(:gitlab_contents_response) do
        fixture("gitlab", "business_files.json")
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, gitlab_url).
          to_return(status: 200,
                    body: gitlab_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, gitlab_repo_url).
          to_return(status: 200,
                    body: fixture("gitlab", "bump_repo.json"),
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, gitlab_raw_changelog_url).
          to_return(status: 200,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      it { is_expected.to eq(expected_pruned_changelog) }
    end

    context "with a bitbucket source" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/src" \
          "?pagelen=100"
      end
      let(:bitbucket_repo_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business"
      end
      let(:bitbucket_raw_changelog_url) do
        "https://bitbucket.org/org/business/raw/default/CHANGELOG.md"
      end

      let(:bitbucket_contents_response) do
        fixture("bitbucket", "business_files.json")
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "bitbucket",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, bitbucket_url).
          to_return(status: 200,
                    body: bitbucket_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, bitbucket_repo_url).
          to_return(status: 200,
                    body: fixture("bitbucket", "bump_repo.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, bitbucket_raw_changelog_url).
          to_return(status: 200,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      it { is_expected.to eq(expected_pruned_changelog) }

      context "with credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "git_source",
            "host" => "bitbucket.org",
            "username" => "greysteil",
            "password" => "secret_token"
          }]
        end

        it "uses the credentials" do
          finder.changelog_text
          expect(WebMock).
            to have_requested(:get, bitbucket_url).
            with(basic_auth: %w(greysteil secret_token))
          expect(WebMock).
            to have_requested(:get, bitbucket_raw_changelog_url).
            with(basic_auth: %w(greysteil secret_token))
        end
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe "#upgrade_guide_url" do
    subject { finder.upgrade_guide_url }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with a upgrade guide" do
        let(:github_response) do
          fixture("github", "business_files_with_upgrade_guide.json")
        end

        context "for a minor update" do
          let(:dependency_version) { "1.4.0" }
          let(:dependency_previous_version) { "1.3.0" }

          it { is_expected.to be_nil }
        end

        context "for a major update" do
          let(:dependency_version) { "1.4.0" }
          let(:dependency_previous_version) { "0.9.0" }

          it "gets the right URL" do
            expect(subject).
              to eq(
                "https://github.com/gocardless/business/blob/master/UPGRADE.md"
              )
          end

          it "caches the call to GitHub" do
            finder.upgrade_guide_url
            finder.upgrade_guide_url
            expect(WebMock).to have_requested(:get, github_url).once
          end
        end
      end

      context "without an upgrade guide" do
        let(:github_response) do
          fixture("github", "business_files.json")
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#upgrade_guide_text" do
    subject(:upgrade_guide_text) { finder.upgrade_guide_text }
    let(:dependency_version) { "1.4.0" }
    let(:dependency_previous_version) { "0.9.0" }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end
      let(:github_upgrade_guide_url) do
        "https://api.github.com/repos/gocardless/business/contents/" \
          "UPGRADE.md?ref=master"
      end
      let(:github_contents_response) do
        fixture("github", "business_files_with_upgrade_guide.json")
      end

      before do
        stub_request(:get, github_url).
          to_return(status: 200,
                    body: github_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_upgrade_guide_url).
          to_return(status: 200,
                    body: fixture("github", "upgrade_guide_contents.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it { is_expected.to eq(fixture("raw", "upgrade.md").sub(/\n*\z/, "")) }

      it "caches the call to GitHub" do
        finder.upgrade_guide_text
        finder.upgrade_guide_text
        expect(WebMock).to have_requested(:get, github_url).once
        expect(WebMock).
          to have_requested(:get, github_upgrade_guide_url).once
      end
    end
  end
end
