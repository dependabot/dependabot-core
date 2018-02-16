# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/message_builder"

RSpec.describe Dependabot::PullRequestCreator::MessageBuilder do
  subject(:namer) do
    described_class.new(
      repo_name: repo,
      dependencies: dependencies,
      files: files,
      github_client: github_client,
      pr_message_footer: pr_message_footer
    )
  end

  let(:repo) { "gocardless/bump" }
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ]
    )
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:pr_message_footer) { nil }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock")
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{repo}" }

  describe "#pr_name" do
    subject(:pr_name) { namer.pr_name }

    context "for an application" do
      context "that doesn't use semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200, body: "[]", headers: json_header)
        end

        it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }

        context "with two dependencies" do
          let(:dependencies) { [dependency, dependency] }

          it { is_expected.to eq("Bump business and business") }
        end

        context "with three dependencies" do
          let(:dependencies) { [dependency, dependency, dependency] }

          it { is_expected.to eq("Bump business, business and business") }
        end

        context "with a directory specified" do
          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("ruby", "gemfiles", "Gemfile"),
              directory: "directory"
            )
          end

          it "includes the directory" do
            expect(pr_name).
              to eq("Bump business from 1.4.0 to 1.5.0 in /directory")
          end
        end

        context "with SHA-1 versions" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
              previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              package_manager: "bundler",
              requirements: [
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
              ],
              previous_requirements: [
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
            )
          end
          let(:new_ref) { nil }
          let(:old_ref) { nil }

          it "truncates the version" do
            expect(pr_name).to eq("Bump business from 2468a0 to cff701")
          end

          context "due to a ref change" do
            let(:new_ref) { "v1.1.0" }
            let(:old_ref) { "v1.0.0" }

            it "uses the refs" do
              expect(pr_name).to eq("Bump business from v1.0.0 to v1.1.0")
            end
          end
        end
      end

      context "that uses semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200,
                      body: fixture("github", "commits_semantic.json"),
                      headers: json_header)
        end

        it { is_expected.to eq("build: bump business from 1.4.0 to 1.5.0") }
      end
    end

    context "for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      context "that doesn't use semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200, body: "[]", headers: json_header)
        end

        it { is_expected.to eq("Update business requirement to ~> 1.5.0") }

        context "with two dependencies" do
          let(:dependencies) { [dependency, dependency] }

          it "includes both dependencies" do
            expect(pr_name).
              to eq("Update requirements for business and business")
          end
        end

        context "with three dependencies" do
          let(:dependencies) { [dependency, dependency, dependency] }

          it "includes all three dependencies" do
            expect(pr_name).
              to eq("Update requirements for business, business and business")
          end
        end

        context "with a directory specified" do
          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("ruby", "gemfiles", "Gemfile"),
              directory: "directory"
            )
          end

          it "includes the directory" do
            expect(pr_name).
              to eq("Update business requirement to ~> 1.5.0 in /directory")
          end
        end
      end

      context "that uses semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200,
                      body: fixture("github", "commits_semantic.json"),
                      headers: json_header)
        end

        it "uses a semantic commit prefix" do
          expect(pr_name).
            to eq("build: update business requirement to ~> 1.5.0")
        end
      end
    end
  end

  describe "#pr_message" do
    subject(:pr_message) { namer.pr_message }

    before do
      business_repo_url = "https://api.github.com/repos/gocardless/business"
      stub_request(:get, watched_repo_url + "/commits").
        to_return(status: 200, body: "[]", headers: json_header)

      stub_request(:get, business_repo_url).
        to_return(status: 200,
                  body: fixture("github", "business_repo.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/contents/").
        to_return(status: 200,
                  body: fixture("github", "business_files.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/tags?per_page=100").
        to_return(status: 200,
                  body: fixture("github", "business_tags.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/releases").
        to_return(status: 200,
                  body: fixture("github", "business_releases.json"),
                  headers: json_header)
      stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
        to_return(status: 200, body: fixture("ruby", "rubygems_response.json"))
    end

    context "for an application" do
      it "has the right text" do
        expect(pr_message).
          to eq(
            "Bumps [business](https://github.com/gocardless/business) "\
            "from 1.4.0 to 1.5.0.\n"\
            "- [Release notes]"\
            "(https://github.com/gocardless/business/releases?after=v1.6.0)\n"\
            "- [Changelog]"\
            "(https://github.com/gocardless/business/blob/master"\
            "/CHANGELOG.md)\n"\
            "- [Commits]"\
            "(https://github.com/gocardless/business/compare/v1.4.0...v1.5.0)"
          )
      end

      context "with SHA-1 versions" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
            previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            package_manager: "bundler",
            requirements: [
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
            ],
            previous_requirements: [
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
          )
        end
        let(:new_ref) { nil }
        let(:old_ref) { nil }

        it "has the right text" do
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) "\
              "from 2468a0 to cff701.\n"\
              "- [Commits]"\
              "(https://github.com/gocardless/business/compare/"\
              "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
              "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2)"
            )
        end

        context "due to a ref change" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "has the right text" do
            expect(pr_message).
              to eq(
                "Bumps [business](https://github.com/gocardless/business) "\
                "from v1.0.0 to v1.1.0.\n"\
                "- [Changelog]"\
                "(https://github.com/gocardless/business/blob/master/"\
                "CHANGELOG.md)\n"\
                "- [Commits]"\
                "(https://github.com/gocardless/business/compare/"\
                "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
                "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2)"
              )
          end
        end
      end

      context "switching from a SHA-1 version to a release" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            package_manager: "bundler",
            requirements: [
              {
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
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
          )
        end

        it "has the right text" do
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) "\
              "from 2468a0 to 1.5.0. This release includes the "\
              "previously tagged commit.\n- [Release notes]"\
              "(https://github.com/gocardless/business/releases?after="\
              "v1.6.0)\n- [Changelog]"\
              "(https://github.com/gocardless/business/blob/master"\
              "/CHANGELOG.md)\n- [Commits]"\
              "(https://github.com/gocardless/business/compare/"\
              "2468a02a6230e59ed1232d95d1ad3ef157195b03...v1.5.0)"
            )
        end
      end

      context "updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "bundler",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.7",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.6",
                groups: [],
                source: nil
              }
            ]
          )
        end

        before do
          statesman_repo_url =
            "https://api.github.com/repos/gocardless/statesman"
          stub_request(:get, statesman_repo_url).
            to_return(status: 200,
                      body: fixture("github", "statesman_repo.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/").
            to_return(status: 200,
                      body: fixture("github", "statesman_files.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/tags?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_tags.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases").
            to_return(status: 200,
                      body: fixture("github", "business_releases.json"),
                      headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) "\
              "and [statesman](https://github.com/gocardless/statesman). "\
              "These dependencies needed to be updated together.\n\n"\
              "Updates `business` from 1.4.0 to 1.5.0"\
              "\n- [Release notes]"\
              "(https://github.com/gocardless/business/releases?after="\
              "v1.6.0)\n- [Changelog]"\
              "(https://github.com/gocardless/business/blob/master"\
              "/CHANGELOG.md)\n- [Commits]"\
              "(https://github.com/gocardless/business/"\
              "compare/v1.4.0...v1.5.0)"\
              "\n\nUpdates `statesman` from 1.6.0 to 1.7.0"\
              "\n- [Release notes]"\
              "(https://github.com/gocardless/business/releases/tag/"\
              "v1.7.0)\n- [Changelog]"\
              "(https://github.com/gocardless/statesman/blob/master"\
              "/CHANGELOG.md)\n- [Commits]"\
              "(https://github.com/gocardless/statesman/commits)"
            )
        end
      end
    end

    context "for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      it "has the right text" do
        expect(pr_message).
          to eq(
            "Updates the requirements on "\
            "[business](https://github.com/gocardless/business) "\
            "to permit the latest version.\n"\
            "- [Release notes]"\
            "(https://github.com/gocardless/business/releases?after=v1.6.0)\n"\
            "- [Changelog]"\
            "(https://github.com/gocardless/business/blob/master"\
            "/CHANGELOG.md)\n"\
            "- [Commits]"\
            "(https://github.com/gocardless/business/compare/v1.4.0...v1.5.0)"
          )
      end

      context "updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "bundler",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.7",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.6",
                groups: [],
                source: nil
              }
            ]
          )
        end

        before do
          statesman_repo_url =
            "https://api.github.com/repos/gocardless/statesman"
          stub_request(:get, statesman_repo_url).
            to_return(status: 200,
                      body: fixture("github", "statesman_repo.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/").
            to_return(status: 200,
                      body: fixture("github", "statesman_files.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/tags?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_tags.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases").
            to_return(status: 200,
                      body: fixture("github", "business_releases.json"),
                      headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message).
            to eq(
              "Updates the requirements on "\
              "[business](https://github.com/gocardless/business) "\
              "and [statesman](https://github.com/gocardless/statesman) "\
              "to permit the latest version.\n\n"\
              "Updates `business` from 1.4.0 to 1.5.0"\
              "\n- [Release notes]"\
              "(https://github.com/gocardless/business/releases?after="\
              "v1.6.0)\n- [Changelog]"\
              "(https://github.com/gocardless/business/blob/master"\
              "/CHANGELOG.md)\n- [Commits]"\
              "(https://github.com/gocardless/business/"\
              "compare/v1.4.0...v1.5.0)"\
              "\n\nUpdates `statesman` from 1.6.0 to 1.7.0"\
              "\n- [Release notes]"\
              "(https://github.com/gocardless/business/releases/tag/"\
              "v1.7.0)\n- [Changelog]"\
              "(https://github.com/gocardless/statesman/blob/master"\
              "/CHANGELOG.md)\n- [Commits]"\
              "(https://github.com/gocardless/statesman/commits)"
            )
        end
      end
    end

    context "with a footer" do
      let(:pr_message_footer) { "I'm a footer!" }

      it { is_expected.to end_with("\n\nI'm a footer!") }
    end
  end

  describe "#commit_message" do
    subject(:commit_message) { namer.commit_message }

    before do
      allow(namer).to receive(:pr_name).and_return("PR name")
      allow(namer).to receive(:pr_message_without_footer).and_return("Message")
    end

    it { is_expected.to eq("PR name\n\nMessage") }
  end
end
