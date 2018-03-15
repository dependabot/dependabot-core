# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/base/commits_finder"

RSpec.describe Dependabot::MetadataFinders::Base::CommitsFinder do
  subject(:builder) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      source: source
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
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:source) do
    Dependabot::MetadataFinders::Base::Source.new(
      host: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end

  describe "#commits_url" do
    subject { builder.commits_url }

    context "with a github repo and old/new tags" do
      let(:dependency_previous_version) { "1.3.0" }

      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "business_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "compare/v1.3.0...v1.4.0")
      end
    end

    context "with a github repo and only a new tag" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "business_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it do
        is_expected.
          to eq("https://github.com/gocardless/business/commits/v1.4.0")
      end
    end

    context "with a github repo and tags with surprising names" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "prefixed_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/business-1.4.0")
      end
    end

    context "with a github repo and tags with no prefix" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "unprefixed_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "commits/1.4.0")
      end
    end

    context "with a github repo and no tags found" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: "[]",
            headers: { "Content-Type" => "application/json" }
          )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/commits")
      end
    end

    context "with a dependency that has a git source" do
      let(:dependency_previous_requirements) do
        [
          {
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business"
            }
          }
        ]
      end
      let(:dependency_requirements) { dependency_previous_requirements }
      let(:dependency_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }
      let(:dependency_previous_version) do
        "7638417db6d59f3c431d3e1f261cc637155684cd"
      end

      it "uses the SHA-1 hashes to build the compare URL" do
        expect(builder.commits_url).
          to eq(
            "https://github.com/gocardless/business/compare/"\
            "7638417db6d59f3c431d3e1f261cc637155684cd..."\
            "cd8274d15fa3ae2ab983129fb037999f264ba9a7"
          )
      end

      context "when the package manager is composer" do
        let(:package_manager) { "composer" }

        let(:dependency_version) { "1.4.0" }
        let(:dependency_previous_version) { "1.3.0" }

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/tags?per_page=100"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_tags.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it do
          is_expected.to eq("https://github.com/gocardless/business/"\
                            "compare/v1.3.0...v1.4.0")
        end
      end

      context "without a previous version" do
        let(:dependency_previous_version) { nil }

        it "uses the new SHA1 hash to build the compare URL" do
          expect(builder.commits_url).
            to eq("https://github.com/gocardless/business/commits/"\
                  "cd8274d15fa3ae2ab983129fb037999f264ba9a7")
        end
      end

      context "for the previous requirement only" do
        let(:dependency_requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        let(:dependency_version) { "1.4.0" }

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/tags?per_page=100"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_tags.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it do
          is_expected.
            to eq("https://github.com/gocardless/business/compare/"\
                  "7638417db6d59f3c431d3e1f261cc637155684cd...v1.4.0")
        end

        context "without a previous version" do
          let(:dependency_previous_version) { nil }

          it "uses the reference specified" do
            expect(builder.commits_url).
              to eq("https://github.com/gocardless/business/commits/v1.4.0")
          end

          context "but with a previously specified reference" do
            let(:dependency_previous_requirements) do
              [
                {
                  file: "Gemfile",
                  requirement: ">= 0",
                  groups: [],
                  source: {
                    type: "git",
                    url: "https://github.com/gocardless/business",
                    ref: "7638417"
                  }
                }
              ]
            end

            it "uses the reference specified" do
              expect(builder.commits_url).
                to eq("https://github.com/gocardless/business/compare/"\
                      "7638417...v1.4.0")
            end
          end
        end
      end
    end

    context "with a gitlab repo" do
      let(:gitlab_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tags"
      end

      let(:gitlab_status) { 200 }
      let(:gitlab_response) { fixture("gitlab", "business_tags.json") }
      let(:source) do
        Dependabot::MetadataFinders::Base::Source.new(
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

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/"\
                            "compare/v1.3.0...v1.4.0")
        end
      end

      context "with only a new tag" do
        let(:dependency_previous_version) { "0.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/commits/v1.4.0")
        end
      end

      context "no tags" do
        let(:dependency_previous_version) { "0.3.0" }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/commits/master")
        end
      end
    end

    context "with a bitbucket repo" do
      let(:bitbucket_url) do
        "https://api.bitbucket.org/2.0/repositories/org/business/refs/tags"\
        "?pagelen=100"
      end

      let(:bitbucket_status) { 200 }
      let(:bitbucket_response) { fixture("bitbucket", "business_tags.json") }
      let(:source) do
        Dependabot::MetadataFinders::Base::Source.new(
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

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/"\
                            "branches/compare/v1.4.0..v1.3.0")
        end
      end

      context "with only a new tag" do
        let(:dependency_previous_version) { "0.3.0" }

        it "gets the right URL" do
          is_expected.
            to eq("https://bitbucket.org/org/business/commits/tag/v1.4.0")
        end
      end

      context "no tags" do
        let(:dependency_previous_version) { "0.3.0" }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/commits")
        end
      end

      context "no previous version" do
        let(:dependency_previous_version) { nil }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/commits")
        end
      end
    end

    context "without a recognised source" do
      let(:source) { nil }
      it { is_expected.to be_nil }
    end
  end

  describe "#commits" do
    subject { builder.commits }

    context "with old and new tags" do
      let(:dependency_previous_version) { "1.3.0" }

      context "with a github repo" do
        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/tags?per_page=100"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_tags.json"),
              headers: { "Content-Type" => "application/json" }
            )
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/"\
            "v1.3.0...v1.4.0"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message:  "Remove SEPA calendar (replaced by TARGET)",
                sha:      "d2eb29beda934c14220146c82f830de2edd63a25",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "d2eb29beda934c14220146c82f830de2edd63a25"
              },
              {
                message:  "Merge pull request #8 from gocardless/"\
                          "rename-sepa-to-ecb\n\nRemove SEPA calendar "\
                          "(replaced by TARGET)",
                sha:      "a5970daf0b824e4c3974e57474b6cf9e39a11d0f",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "a5970daf0b824e4c3974e57474b6cf9e39a11d0f"
              },
              {
                message:  "Spacing",
                sha:      "0bfb8c3f0d2701abf9248185beeb8adf643374f6",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "0bfb8c3f0d2701abf9248185beeb8adf643374f6"
              },
              {
                message:  "Allow custom calendars",
                sha:      "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076"
              },
              {
                message:  "Merge pull request #9 from gocardless/"\
                          "custom-calendars\n\nAllow custom calendars",
                sha:      "7abe4c2dc0161904c40c221a48999d12995fbea7",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "7abe4c2dc0161904c40c221a48999d12995fbea7"
              },
              {
                message:  "Bump version to v1.4.0",
                sha:      "26f4887ec647493f044836363537e329d9d213aa",
                html_url: "https://github.com/gocardless/business/commit/"\
                          "26f4887ec647493f044836363537e329d9d213aa"
              }
            ]
          )
        end

        context "that 404s" do
          before do
            response = {
              message: "No common ancestor between v4.7.0 and 5.0.8."
            }.to_json

            stub_request(
              :get,
              "https://api.github.com/repos/gocardless/business/compare/"\
              "v1.3.0...v1.4.0"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 404,
                body: response,
                headers: { "Content-Type" => "application/json" }
              )
          end

          it { is_expected.to eq([]) }
        end
      end

      context "with a bitbucket repo" do
        let(:bitbucket_tags_url) do
          "https://api.bitbucket.org/2.0/repositories/org/business/refs/tags"\
          "?pagelen=100"
        end
        let(:bitbucket_compare_url) do
          "https://api.bitbucket.org/2.0/repositories/org/business/commits/"\
          "?exclude=v1.3.0&include=v1.4.0"
        end

        let(:bitbucket_tags) { fixture("bitbucket", "business_tags.json") }
        let(:bitbucket_compare) do
          fixture("bitbucket", "business_compare_commits.json")
        end

        let(:source) do
          Dependabot::MetadataFinders::Base::Source.new(
            host: "bitbucket",
            repo: "org/#{dependency_name}"
          )
        end

        before do
          stub_request(:get, bitbucket_tags_url).
            to_return(status: 200,
                      body: bitbucket_tags,
                      headers: { "Content-Type" => "application/json" })
          stub_request(:get, bitbucket_compare_url).
            to_return(status: 200,
                      body: bitbucket_compare,
                      headers: { "Content-Type" => "application/json" })
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message:  "Added signature for changeset f275e318641f",
                sha:      "deae742eacfa985bd20f47a12a8fee6ce2e0447c",
                html_url: "https://bitbucket.org/ged/ruby-pg/commits/"\
                          "deae742eacfa985bd20f47a12a8fee6ce2e0447c"
              },
              {
                message:  "Eliminate use of deprecated PGError constant from "\
                          "specs",
                sha:      "f275e318641f185b8a15a2220e7c189b1769f84c",
                html_url: "https://bitbucket.org/ged/ruby-pg/commits/"\
                          "f275e318641f185b8a15a2220e7c189b1769f84c"
              }
            ]
          )
        end
      end

      context "with a gitlab repo" do
        let(:gitlab_tags_url) do
          "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/tags"
        end
        let(:gitlab_compare_url) do
          "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/"\
          "compare?from=v1.3.0&to=v1.4.0"
        end

        let(:gitlab_tags) { fixture("gitlab", "business_tags.json") }
        let(:gitlab_compare) do
          fixture("gitlab", "business_compare_commits.json")
        end
        let(:source) do
          Dependabot::MetadataFinders::Base::Source.new(
            host: "gitlab",
            repo: "org/#{dependency_name}"
          )
        end
        before do
          stub_request(:get, gitlab_tags_url).
            to_return(status: 200,
                      body: gitlab_tags,
                      headers: { "Content-Type" => "application/json" })
          stub_request(:get, gitlab_compare_url).
            to_return(status: 200,
                      body: gitlab_compare,
                      headers: { "Content-Type" => "application/json" })
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message:  "Add find command\n",
                sha:      "8d7d08fb9a7a439b3e6a1e6a1a34cbdb4273de87",
                html_url: "https://gitlab.com/org/business/commit/"\
                          "8d7d08fb9a7a439b3e6a1e6a1a34cbdb4273de87"
              },
              {
                message:  "...\n",
                sha:      "4ac81646582f254b3e86653b8fcd5eda6d8bb45d",
                html_url: "https://gitlab.com/org/business/commit/"\
                          "4ac81646582f254b3e86653b8fcd5eda6d8bb45d"
              },
              {
                message:  "MP version\n",
                sha:      "4e5081f867631f10d8a29dc6853a052f52241fab",
                html_url: "https://gitlab.com/org/business/commit/"\
                          "4e5081f867631f10d8a29dc6853a052f52241fab"
              },
              {
                message:  "BUG: added 'force_consistent' keyword argument "\
                          "with default True\n\nThe bug fix is necessayry to "\
                          "pass the test turbomole_h3o2m.py.\n",
                sha:      "e718899ddcdc666311d08497401199e126428163",
                html_url: "https://gitlab.com/org/business/commit/"\
                          "e718899ddcdc666311d08497401199e126428163"
              }
            ]
          )
        end
      end
    end

    context "with only a new tag" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "business_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it { is_expected.to eq([]) }
    end

    context "with no tags found" do
      before do
        stub_request(
          :get,
          "https://api.github.com/repos/gocardless/business/tags?per_page=100"
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: "[]",
            headers: { "Content-Type" => "application/json" }
          )
      end

      it { is_expected.to eq([]) }
    end

    context "without a recognised source" do
      let(:source) { nil }
      it { is_expected.to eq([]) }
    end
  end
end
