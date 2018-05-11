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
  let(:credentials) do
    [{
      "type" => "git",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:source) do
    Dependabot::Source.new(
      host: "github",
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

  describe "#changelog_url" do
    subject { finder.changelog_url }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

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
      end

      context "without a changelog" do
        let(:github_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }
      end

      context "with a docs folder" do
        let(:github_response) { fixture("github", "scrapy_files.json") }
        before do
          stub_request(:get, github_url + "docs").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: github_status,
                      body: fixture("github", "scrapy_docs_files.json"),
                      headers: { "Content-Type" => "application/json" })
        end

        it "gets the right URL" do
          expect(subject).
            to eq("https://github.com/scrapy/scrapy/blob/master/docs/news.rst")
        end

        it "caches the call to GitHub" do
          finder.changelog_url
          finder.changelog_url
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "with a directory" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:source) do
          Dependabot::Source.new(
            host: "github",
            repo: "gocardless/#{dependency_name}",
            directory: "packages/stryker"
          )
        end
        before do
          stub_request(:get, github_url + "packages/stryker").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: github_status,
                      body: fixture("github", "business_module_files.json"),
                      headers: { "Content-Type" => "application/json" })
        end

        it "gets the right URL" do
          expect(subject).
            to eq("https://github.com/gocardless/business/blob/master/module"\
                  "/CHANGELOG.md")
        end

        it "caches the call to GitHub" do
          finder.changelog_url
          finder.changelog_url
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        it { is_expected.to be_nil }
      end

      context "for a git dependency" do
        let(:github_response) { fixture("github", "business_files.json") }
        let(:dependency_requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: new_ref
              }
            }
          ]
        end
        let(:dependency_previous_requirements) do
          [
            {
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: old_ref
              }
            }
          ]
        end
        let(:new_ref) { "master" }
        let(:old_ref) { "master" }

        it { is_expected.to be_nil }

        context "when the package manager is composer" do
          let(:package_manager) { "composer" }

          it "finds the changelog as normal" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/"\
                    "CHANGELOG.md")
          end
        end

        context "when the ref has changed" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "finds the changelog as normal" do
            expect(subject).
              to eq("https://github.com/gocardless/business/blob/master/"\
                    "CHANGELOG.md")
          end
        end
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_files.json") }
      let(:source) do
        Dependabot::Source.new(
          host: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, gitlab_url).
          to_return(status: gitlab_status,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
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

    context "with a bitbucket source" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/src"\
        "?pagelen=100"
      end

      let(:bitbucket_status) { 200 }
      let(:bitbucket_response) { fixture("bitbucket", "business_files.json") }
      let(:source) do
        Dependabot::Source.new(
          host: "bitbucket",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, bitbucket_url).
          to_return(status: bitbucket_status,
                    body: bitbucket_response,
                    headers: { "Content-Type" => "application/json" })
      end

      it "gets the right URL" do
        is_expected.to eq(
          "https://bitbucket.org/org/business/src/master/CHANGELOG.md"
        )
      end

      context "that can't be found exists" do
        let(:bitbucket_status) { 404 }
        it { is_expected.to be_nil }
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe "#changelog_text" do
    subject(:changelog_text) { finder.changelog_text }
    let(:dependency_version) { "1.4.0" }
    let(:dependency_previous_version) { "1.0.0" }

    let(:expected_pruned_changelog) do
      "## 1.4.0 - December 24, 2014\n\n"\
      "- Add support for custom calendar load paths\n"\
      "- Remove the 'sepa' calendar\n\n\n"\
      "## 1.3.0 - December 2, 2014\n\n"\
      "- Add `Calendar#previous_business_day`\n\n\n"\
      "## 1.2.0 - November 15, 2014\n\n"\
      "- Add TARGET calendar\n\n\n"\
      "## 1.1.0 - September 30, 2014\n\n"\
      "- Add 2015 holiday definitions"
    end

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end
      let(:github_changelog_url) do
        "https://api.github.com/repos/gocardless/business/contents/CHANGELOG.md"
      end
      let(:github_contents_response) do
        fixture("github", "business_files.json")
      end
      let(:changelog_body) { fixture("github", "changelog_contents.json") }

      before do
        stub_request(:get, github_url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: github_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_changelog_url).
          with(headers: { "Authorization" => "token token" }).
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

        context "that is in reverse order" do
          let(:changelog_body) do
            fixture("github", "changelog_contents_reversed.json")
          end
          let(:dependency_version) { "1.11.1" }
          let(:dependency_previous_version) { "1.10.0" }

          # Ideally we'd prune the 1.10.0 entry off, but it's tricky.
          let(:expected_pruned_changelog) do
            "## 1.10.0 - September 20, 2017\n\n"\
            "- Add 2018-2019 Betalingsservice holiday definitions\n\n"\
            "## 1.11.1 - December 20, 2017\n\n"\
            "- Add 2017-2018 BECS holiday definitions"
          end

          it { is_expected.to eq(expected_pruned_changelog) }
        end

        context "when the dependency has no previous version" do
          let(:dependency_previous_version) { nil }

          it "gets the right content" do
            expect(changelog_text).to start_with("## 1.4.0 - December 24, 2014")
            expect(changelog_text).to end_with("- Initial public release")
          end
        end

        context "with no relevant versions" do
          let(:dependency_version) { "1.13.0" }
          let(:dependency_previous_version) { "1.12.0" }

          it { is_expected.to be_nil }
        end

        context "with relevant releases but not exact match" do
          let(:dependency_version) { "1.13.0" }
          let(:dependency_previous_version) { "1.4.5" }

          it "gets the right content" do
            expect(changelog_text).to start_with("## 1.11.1")
            expect(changelog_text).to end_with("- Initial public release")
          end
        end

        context "when the changelog doesn't include the previous version" do
          let(:dependency_previous_version) { "0.0.1" }

          it "gets the right content" do
            expect(changelog_text).to start_with("## 1.4.0 - December 24, 2014")
            expect(changelog_text).to end_with("- Initial public release")
          end
        end

        context "when the changelog doesn't include the new version" do
          let(:dependency_version) { "2.0.0" }

          it "gets the right content" do
            expect(changelog_text).to start_with("## 1.11.1 - December 20")
            expect(changelog_text).to end_with("- Add 2015 holiday definitions")
          end

          context "and the previous version is the latest in the changelog" do
            let(:dependency_previous_version) { "1.11.1" }
            it { is_expected.to be_nil }
          end
        end

        context "for a git dependency" do
          let(:dependency_requirements) do
            [
              {
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  ref: new_ref
                }
              }
            ]
          end
          let(:dependency_previous_requirements) do
            [
              {
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  ref: old_ref
                }
              }
            ]
          end
          let(:new_ref) { "master" }
          let(:old_ref) { "master" }
          let(:dependency_version) { "aa12b317" }
          let(:dependency_previous_version) { "a1a123b1" }

          it { is_expected.to be_nil }

          context "when the package manager is composer" do
            let(:package_manager) { "composer" }
            let(:raw_changelog) { fixture("raw", "changelog.md") }
            it { is_expected.to eq(raw_changelog.sub(/\n*\z/, "")) }
          end

          context "when the ref has changed" do
            let(:new_ref) { "v1.4.0" }
            let(:old_ref) { "v1.0.0" }

            it { is_expected.to eq(expected_pruned_changelog) }
          end
        end
      end

      context "without a changelog" do
        let(:github_contents_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tree"
      end
      let(:gitlab_raw_changelog_url) do
        "https://gitlab.com/org/business/raw/master/CHANGELOG.md"
      end

      let(:gitlab_contents_response) do
        fixture("gitlab", "business_files.json")
      end
      let(:source) do
        Dependabot::Source.new(
          host: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, gitlab_url).
          to_return(status: 200,
                    body: gitlab_contents_response,
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
        "https://api.bitbucket.org/2.0/repositories/org/business/src"\
        "?pagelen=100"
      end
      let(:bitbucket_raw_changelog_url) do
        "https://bitbucket.org/org/business/raw/master/CHANGELOG.md"
      end

      let(:bitbucket_contents_response) do
        fixture("bitbucket", "business_files.json")
      end
      let(:source) do
        Dependabot::Source.new(
          host: "bitbucket",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, bitbucket_url).
          to_return(status: 200,
                    body: bitbucket_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, bitbucket_raw_changelog_url).
          to_return(status: 200,
                    body: fixture("raw", "changelog.md"),
                    headers: { "Content-Type" => "text/plain; charset=utf-8" })
      end

      it { is_expected.to eq(expected_pruned_changelog) }
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
          with(headers: { "Authorization" => "token token" }).
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
            finder.changelog_url
            finder.changelog_url
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
        "https://api.github.com/repos/gocardless/business/contents/UPGRADE.md"
      end
      let(:github_contents_response) do
        fixture("github", "business_files_with_upgrade_guide.json")
      end

      before do
        stub_request(:get, github_url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: github_contents_response,
                    headers: { "Content-Type" => "application/json" })
        stub_request(:get, github_upgrade_guide_url).
          with(headers: { "Authorization" => "token token" }).
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
