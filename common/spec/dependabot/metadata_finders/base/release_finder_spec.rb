# frozen_string_literal: true

require "octokit"
require "gitlab"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/metadata_finders/base/release_finder"

RSpec.describe Dependabot::MetadataFinders::Base::ReleaseFinder do
  subject(:finder) do
    described_class.new(
      source: source,
      dependency: dependency,
      credentials: credentials
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      previous_version: dependency_previous_version,
      package_manager: "dummy"
    )
  end
  let(:requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_previous_version) { "1.0.0" }
  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end

  describe "#releases_url" do
    subject { finder.releases_url }

    context "with a github repo" do
      it "gets the right URL" do
        expect(subject).to eq("https://github.com/gocardless/business/releases")
      end
    end

    context "with a gitlab source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      it "gets the right URL" do
        expect(subject).to eq("https://gitlab.com/org/business/tags")
      end
    end

    context "without a source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end

    context "with an azure source" do
      let(:source) do
        Dependabot::Source.
          from_url("https://dev.azure.com/saigkill/_git/hoe-manns")
      end

      it "gets the right URL" do
        expect(subject).
          to eq("https://dev.azure.com/saigkill/_git/hoe-manns/tags")
      end
    end

    context "with a codecommit source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "codecommit",
          repo: "repos/#{dependency_name}"
        )
      end

      it { is_expected.to be_nil }
    end
  end

  describe "#releases_text" do
    subject { finder.releases_text }

    context "with a github repo" do
      let(:github_url) do
        "https://api.github.com/repos/gocardless/#{dependency_name}/" \
          "releases?per_page=100"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with releases" do
        let(:github_response) { fixture("github", "business_releases.json") }

        context "when the release is present" do
          let(:dependency_version) { "1.8.0" }

          context "and is updating from one version previous" do
            let(:dependency_previous_version) { "1.7.0" }

            it "gets the right text" do
              expect(subject).
                to eq(
                  "## v1.8.0\n" \
                  "- Add 2018-2027 TARGET holiday defintions\n" \
                  "- Add 2018-2027 Bankgirot holiday defintions"
                )
            end

            it "caches the call to GitHub" do
              finder.releases_text
              finder.releases_text
              expect(WebMock).to have_requested(:get, github_url).once
            end

            context "with git tags" do
              let(:dependency) do
                Dependabot::Dependency.new(
                  name: dependency_name,
                  version: "a" * 40,
                  requirements: [{
                    file: "Gemfile",
                    requirement: nil,
                    groups: [],
                    source: {
                      type: "git",
                      url: "https://github.com/actions/setup-node",
                      ref: "v1.8.0",
                      branch: nil
                    }
                  }],
                  previous_requirements: [{
                    file: "Gemfile",
                    requirement: nil,
                    groups: [],
                    source: {
                      type: "git",
                      url: "https://github.com/actions/setup-node",
                      ref: "v1.7.0",
                      branch: nil
                    }
                  }],
                  previous_version: nil,
                  package_manager: "dummy"
                )
              end

              it "gets the right text" do
                expect(subject).
                  to eq(
                    "## v1.8.0\n" \
                    "- Add 2018-2027 TARGET holiday defintions\n" \
                    "- Add 2018-2027 Bankgirot holiday defintions"
                  )
              end
            end

            context "but prefixed" do
              let(:github_response) do
                fixture("github", "prefixed_releases.json")
              end

              it "still gets the right text" do
                expect(subject).
                  to eq(
                    "## business-1.8.0\n" \
                    "- Add 2018-2027 TARGET holiday defintions\n" \
                    "- Add 2018-2027 Bankgirot holiday defintions"
                  )
              end
            end

            context "but is blank" do
              let(:dependency_version) { "1.7.0" }
              let(:dependency_previous_version) { "1.7.0.beta" }

              it { is_expected.to be_nil }
            end

            context "but is nil" do
              let(:dependency_version) { "1.7.0.beta" }
              let(:dependency_previous_version) { "1.7.0.alpha" }

              it { is_expected.to be_nil }
            end

            context "but has blank names" do
              let(:github_response) do
                fixture("github", "releases_no_names.json")
              end

              it "falls back to the tag name" do
                expect(subject).
                  to eq(
                    "## v1.8.0\n" \
                    "- Add 2018-2027 TARGET holiday defintions\n" \
                    "- Add 2018-2027 Bankgirot holiday defintions"
                  )
              end
            end

            context "with a numeric prefix (rare)" do
              let(:github_response) do
                fixture("github", "releases_number_prefix.json")
              end

              it { is_expected.to be_nil }
            end

            context "but has tag names with dashes, and it's Java" do
              let(:github_response) do
                fixture("github", "releases_dash_tags.json")
              end
              let(:dependency_version) { "6.5.1" }
              let(:dependency_previous_version) { "6.4.0" }

              it "falls back to the tag name" do
                expect(subject).
                  to eq(
                    "## JasperReports 6.5.1\n" \
                    "Body for 6.5.1\n" \
                    "\n" \
                    "## JasperReports 6.5.0\n" \
                    "Body for 6.5.0\n" \
                    "\n" \
                    "## JasperReports 6.4.3\n" \
                    "Body for 6.4.3\n" \
                    "\n" \
                    "## JasperReports 6.4.1\n" \
                    "Body for 6.4.1"
                  )
              end
            end
          end

          context "and is updating from several versions previous" do
            let(:dependency_previous_version) { "1.6.0" }

            it "gets the right text" do
              expect(subject).
                to eq(
                  "## v1.8.0\n" \
                  "- Add 2018-2027 TARGET holiday defintions\n" \
                  "- Add 2018-2027 Bankgirot holiday defintions\n" \
                  "\n" \
                  "## v1.7.0\n" \
                  "No release notes provided.\n" \
                  "\n" \
                  "## v1.7.0.beta\n" \
                  "No release notes provided.\n" \
                  "\n" \
                  "## v1.7.0.alpha\n" \
                  "No release notes provided."
                )
            end

            context "but all versions are blank or nil" do
              let(:dependency_version) { "1.7.0" }
              it { is_expected.to be_nil }
            end

            context "when the latest version is blank, but not all are" do
              let(:dependency_version) { "1.7.0" }
              let(:dependency_previous_version) { "1.5.0" }

              it "gets the right text" do
                expect(subject).
                  to eq(
                    "## v1.7.0\n" \
                    "No release notes provided.\n" \
                    "\n" \
                    "## v1.7.0.beta\n" \
                    "No release notes provided.\n" \
                    "\n" \
                    "## v1.7.0.alpha\n" \
                    "No release notes provided.\n" \
                    "\n" \
                    "## v1.6.0\n" \
                    "Mad props to @greysteil and " \
                    "[@hmarr](https://github.com/hmarr) for the " \
                    "@angular/scope work - " \
                    "see [changelog](CHANGELOG.md)."
                  )
              end
            end
          end

          context "and the previous release doesn't have a github release" do
            let(:dependency_previous_version) { "1.5.1" }

            it "uses the version number to filter the releases" do
              expect(subject).
                to eq(
                  "## v1.8.0\n" \
                  "- Add 2018-2027 TARGET holiday defintions\n" \
                  "- Add 2018-2027 Bankgirot holiday defintions\n" \
                  "\n" \
                  "## v1.7.0\n" \
                  "No release notes provided.\n" \
                  "\n" \
                  "## v1.7.0.beta\n" \
                  "No release notes provided.\n" \
                  "\n" \
                  "## v1.7.0.alpha\n" \
                  "No release notes provided.\n" \
                  "\n" \
                  "## v1.6.0\n" \
                  "Mad props to @greysteil and " \
                  "[@hmarr](https://github.com/hmarr) for the " \
                  "@angular/scope work - " \
                  "see [changelog](CHANGELOG.md)."
                )
            end
          end

          context "updating from no previous release to new release", :vcr do
            let(:dependency_name) { "actions/checkout" }
            let(:dependency_version) do
              "aabbfeb2ce60b5bd82389903509092c4648a9713"
            end
            let(:dependency_previous_version) { nil }
            let(:requirements) do
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
            let(:previous_requirements) do
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
                repo: dependency_name
              )
            end

            it { is_expected.to start_with("## v2.2.0") }
          end
        end

        context "when the release is not present" do
          let(:dependency_version) { "1.9.0" }
          let(:dependency_previous_version) { "1.8.0" }
          it { is_expected.to be_nil }

          context "and there is a blank named release that needs excluding" do
            let(:github_response) do
              fixture("github", "releases_ember_cp.json")
            end
            let(:dependency_version) { "3.5.3" }
            let(:dependency_previous_version) { "3.5.2" }
            it { is_expected.to be_nil }
          end

          context "but has 'Fix #123' names" do
            let(:dependency_version) { "2.1.0" }
            let(:dependency_previous_version) { "2.0.0" }
            let(:github_response) do
              fixture("github", "releases_fix_names.json")
            end

            it "figures out not to use the 'Fix #123' names" do
              expect(subject).to be_nil
            end
          end
        end

        context "when the release has a bad name" do
          let(:dependency_version) { "1.8.0" }
          let(:dependency_previous_version) { "1.7.0" }
          let(:github_response) do
            fixture("github", "business_releases_bad_name.json")
          end
          it "gets the right text" do
            expect(subject).
              to eq(
                "## v1.7.0\n" \
                "- Add 2018-2027 TARGET holiday defintions\n" \
                "- Add 2018-2027 Bankgirot holiday defintions"
              )
          end
        end

        context "when the tags are for a monorepo" do
          let(:dependency_name) { "Flurl.Http" }
          let(:dependency_version) { "2.4.0" }
          let(:dependency_previous_version) { "2.3.2" }
          let(:github_response) { fixture("github", "releases_monorepo.json") }
          it "gets the right text" do
            expect(subject).
              to eq(
                "## Flurl.Http 2.4.0\n" \
                "- Improved `ConnectionLeaseTimeout` implementation (#330)"
              )
          end
        end

        context "without GitHub credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "bitbucket.org",
              "username" => "greysteil",
              "password" => "secret_token"
            }]
          end

          context "when authentication fails" do
            before { stub_request(:get, github_url).to_return(status: 404) }
            it { is_expected.to be_nil }
          end

          context "when authentication succeeds" do
            before do
              stub_request(:get, github_url).
                to_return(status: github_status,
                          body: github_response,
                          headers: { "Content-Type" => "application/json" })
            end

            let(:github_response) do
              fixture("github", "business_releases.json")
            end

            let(:dependency_version) { "1.8.0" }
            let(:dependency_previous_version) { "1.7.0" }

            it "gets the right text" do
              expect(subject).
                to eq(
                  "## v1.8.0\n" \
                  "- Add 2018-2027 TARGET holiday defintions\n" \
                  "- Add 2018-2027 Bankgirot holiday defintions"
                )
            end
          end
        end
      end

      context "when access to the repo is blocked" do
        let(:github_response) { fixture("github", "dmca_takedown.json") }
        let(:github_status) { 451 }

        it { is_expected.to be_nil }
      end
    end

    context "with a gitlab source" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tags"
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      let(:gitlab_response) { fixture("gitlab", "business_tags.json") }

      before do
        stub_request(:get, gitlab_url).
          to_return(status: 200,
                    body: gitlab_response,
                    headers: { "Content-Type" => "application/json" })
      end

      let(:dependency_version) { "1.4.0" }
      let(:dependency_previous_version) { "1.3.0" }

      it "gets the right text" do
        expect(subject).
          to eq(
            "## v1.4.0\n" \
            "Some release notes"
          )
      end
    end

    context "with an azure source" do
      let(:source) do
        Dependabot::Source.
          from_url("https://dev.azure.com/saigkill/_git/hoe-manns")
      end

      it { is_expected.to be_nil }
    end

    context "without a recognised source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end
end
