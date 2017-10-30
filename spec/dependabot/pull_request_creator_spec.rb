# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator"

RSpec.describe Dependabot::PullRequestCreator do
  subject(:creator) do
    Dependabot::PullRequestCreator.new(repo: repo,
                                       base_commit: base_commit,
                                       dependency: dependency,
                                       files: files,
                                       github_client: github_client)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ],
      previous_requirements: [
        { file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }
      ]
    )
  end
  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile, gemfile_lock] }
  let(:base_commit) { "basecommitsha" }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

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
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }

  before do
    stub_request(:get, watched_repo_url).
      to_return(status: 200,
                body: fixture("github", "bump_repo.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
      to_return(status: 404,
                body: fixture("github", "not_found.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/trees").
      to_return(status: 200,
                body: fixture("github", "create_tree.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/commits").
      to_return(status: 200,
                body: fixture("github", "create_commit.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/refs").
      to_return(status: 200,
                body: fixture("github", "create_ref.json"),
                headers: json_header)
    stub_request(:get, "#{watched_repo_url}/labels?per_page=100").
      to_return(status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/pulls").
      to_return(status: 200,
                body: fixture("github", "create_pr.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/issues/1347/labels").
      to_return(status: 200,
                body: fixture("github", "create_label.json"),
                headers: json_header)

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

  describe "#create" do
    context "without a previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          package_manager: "bundler",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        )
      end

      it "errors out on initialization" do
        expect { creator }.to raise_error(/must have a/)
      end
    end

    it "pushes a commit to GitHub" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/trees").
        with(body: {
               base_tree: "basecommitsha",
               tree: [
                 {
                   path: "Gemfile",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "gemfiles", "Gemfile")
                 },
                 {
                   path: "Gemfile.lock",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "lockfiles", "Gemfile.lock")
                 }
               ]
             })

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits")
    end

    context "with a submodule" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "manifesto",
            type: "submodule",
            content: "sha1"
          )
        ]
      end

      it "pushes a commit to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/trees").
          with(body: {
                 base_tree: "basecommitsha",
                 tree: [
                   {
                     path: "manifesto",
                     mode: "160000",
                     type: "commit",
                     sha: "sha1"
                   }
                 ]
               })

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits")
      end
    end

    it "has the right commit message" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits").
        with(body: {
               parents: ["basecommitsha"],
               tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
               message: /Bump business from 1.4.0 to 1\.5\.0\n\nBumps \[busines/
             })
    end

    it "creates a branch for that commit" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/refs").
        with(body: {
               ref: "refs/heads/dependabot/bundler/business-1.5.0",
               sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
             })
    end

    it "creates a PR with the right details" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/pulls").
        with(
          body: {
            base: "master",
            head: "dependabot/bundler/business-1.5.0",
            title: "Bump business from 1.4.0 to 1.5.0",
            body: "Bumps [business](https://github.com/gocardless/business) "\
                  "from 1.4.0 to 1.5.0.\n- [Release notes]"\
                  "(https://github.com/gocardless/business/releases?after="\
                  "v1.6.0)\n- [Changelog]"\
                  "(https://github.com/gocardless/business/blob/master"\
                  "/CHANGELOG.md)\n- [Commits]"\
                  "(https://github.com/gocardless/business/"\
                  "compare/v1.4.0...v1.5.0)"
          }
        )
    end

    it "labels the PR" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/issues/1347/labels").
        with(body: '["dependencies"]')
    end

    it "returns details of the created pull request" do
      expect(creator.create.title).to eq("new-feature")
      expect(creator.create.number).to eq(1347)
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
                url: "https://github.com/gocardless/business"
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
                url: "https://github.com/gocardless/business"
              }
            }
          ]
        )
      end
      let(:branch_name) { "dependabot/bundler/business-cff701" }

      it "creates a branch for that commit" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/refs").
          with(body: {
                 ref: "refs/heads/dependabot/bundler/business-cff701",
                 sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
               })
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-cff701",
              title: "Bump business from 2468a0 to cff701",
              body: "Bumps [business](https://github.com/gocardless/business) "\
                    "from 2468a0 to cff701.\n- [Commits]"\
                    "(https://github.com/gocardless/business/compare/"\
                    "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
                    "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2)"
            }
          )
      end

      context "due to a ref change" do
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
                  ref: "v1.1.0"
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
                  ref: "v1.0.0"
                }
              }
            ]
          )
        end
        let(:branch_name) { "dependabot/bundler/business-v1.1.0" }

        it "creates a branch for that commit" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{watched_repo_url}/git/refs").
            with(body: {
                   ref: "refs/heads/dependabot/bundler/business-v1.1.0",
                   sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
                 })
        end

        it "creates a PR with the right details" do
          creator.create

          expect(WebMock).
            to have_requested(:post, "#{watched_repo_url}/pulls").
            with(
              body: {
                base: "master",
                head: "dependabot/bundler/business-v1.1.0",
                title: "Bump business from v1.0.0 to v1.1.0",
                body: "Bumps [business](https://github.com/gocardless/"\
                      "business) from v1.0.0 to v1.1.0.\n- [Changelog]"\
                      "(https://github.com/gocardless/business/blob/master"\
                      "/CHANGELOG.md)\n- [Commits]"\
                      "(https://github.com/gocardless/business/compare/"\
                      "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
                      "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2)"
              }
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
      let(:branch_name) { "dependabot/bundler/business-1.5.0" }

      it "creates a branch for that commit" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/refs").
          with(body: {
                 ref: "refs/heads/dependabot/bundler/business-1.5.0",
                 sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
               })
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-1.5.0",
              title: "Bump business from 2468a0 to 1.5.0",
              body: "Bumps [business](https://github.com/gocardless/business) "\
                    "from 2468a0 to 1.5.0. This release includes the "\
                    "previously tagged commit.\n- [Release notes]"\
                    "(https://github.com/gocardless/business/releases?after="\
                    "v1.6.0)\n- [Changelog]"\
                    "(https://github.com/gocardless/business/blob/master"\
                    "/CHANGELOG.md)\n- [Commits]"\
                    "(https://github.com/gocardless/business/compare/"\
                    "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
                    "v1.5.0)"
            }
          )
      end
    end

    context "when the 'dependencies' label doesn't yet exist" do
      before do
        stub_request(:get, "#{watched_repo_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_without_dependencies.json"),
                    headers: json_header)
        stub_request(:post, "#{watched_repo_url}/labels").
          to_return(status: 201,
                    body: fixture("github", "create_label.json"),
                    headers: json_header)
      end

      it "creates a 'dependencies' label" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/labels").
          with(body: { name: "dependencies", color: "0025ff" })
      end

      context "when there's a race and we lose" do
        before do
          stub_request(:post, "#{watched_repo_url}/labels").
            to_return(status: 422,
                      body: fixture("github", "label_already_exists.json"),
                      headers: json_header)
        end

        it "quietly ignores losing the race" do
          expect(creator.create.title).to eq("new-feature")
        end
      end
    end

    context "for a library" do
      let(:files) { [gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "example.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          package_manager: "bundler",
          requirements: [
            {
              file: "some.gemspec",
              requirement: ">= 1.0, < 3.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "some.gemspec",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        )
      end
      let(:branch_name) { "dependabot/bundler/business-gte-1.0-and-lt-3.0" }

      context "without a previous requirement" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            package_manager: "bundler",
            requirements: [
              {
                file: "some.gemspec",
                requirement: ">= 1.0, < 3.0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "some.gemspec",
                requirement: ">= 1.0, < 3.0",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "errors out on initialization" do
          expect { creator }.to raise_error(/must have a/)
        end
      end

      it "has the right commit message" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits").
          with(body: {
                 parents: ["basecommitsha"],
                 tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
                 message: /Update business requirement to >= 1/
               })
      end

      it "creates a branch for that commit" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/refs").
          with(body: {
                 ref: "refs/heads/#{branch_name}",
                 sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
               })
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-gte-1.0-and-lt-3.0",
              title: "Update business requirement to >= 1.0, < 3.0",
              body: "Updates the requirements on "\
                    "[business](https://github.com/gocardless/business) "\
                    "to permit the latest version.\n- [Release notes]"\
                    "(https://github.com/gocardless/business/releases?after="\
                    "v1.6.0)\n- [Changelog]"\
                    "(https://github.com/gocardless/business/blob/master"\
                    "/CHANGELOG.md)\n- [Commits]"\
                    "(https://github.com/gocardless/business/commits/v1.5.0)"
            }
          )
      end
    end

    context "for a Gemfile only" do
      let(:files) { [gemfile] }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          package_manager: "bundler",
          requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }
          ],
          previous_requirements: [
            {
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }
          ]
        )
      end
      let(:branch_name) { "dependabot/bundler/business-tw-1.5.0" }

      context "without a previous requirement" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            package_manager: "bundler",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil
              }
            ],
            previous_requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil
              }
            ]
          )
        end

        it "errors out on initialization" do
          expect { creator }.to raise_error(/must have a/)
        end
      end

      it "has the right commit message" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits").
          with(body: {
                 parents: ["basecommitsha"],
                 tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
                 message: /Update business requirement to ~> 1/
               })
      end

      it "creates a branch for that commit" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/refs").
          with(body: {
                 ref: "refs/heads/#{branch_name}",
                 sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
               })
      end

      it "creates a PR with the right details" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-tw-1.5.0",
              title: "Update business requirement to ~> 1.5.0",
              body: "Updates the requirements on "\
                    "[business](https://github.com/gocardless/business) "\
                    "to permit the latest version.\n- [Release notes]"\
                    "(https://github.com/gocardless/business/releases?after="\
                    "v1.6.0)\n- [Changelog]"\
                    "(https://github.com/gocardless/business/blob/master"\
                    "/CHANGELOG.md)\n- [Commits]"\
                    "(https://github.com/gocardless/business/commits/v1.5.0)"
            }
          )
      end
    end

    context "when a branch for this update already exists" do
      before do
        stub_request(:get, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
          to_return(status: 200,
                    body: fixture("github", "check_ref.json"),
                    headers: json_header)
      end

      specify { expect { creator.create }.to_not raise_error }

      it "doesn't push changes to the branch" do
        creator.create

        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/git/trees")
      end

      it "doesn't try to re-create the PR" do
        creator.create
        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/pulls")
      end
    end

    context "when there's a race to create the new branch, and we lose" do
      before do
        stub_request(:post, "#{watched_repo_url}/git/refs").
          to_return(status: 422,
                    body: fixture("github", "create_ref_error.json"),
                    headers: json_header)
      end

      specify { expect { creator.create }.to_not raise_error }

      it "doesn't try to re-create the PR" do
        creator.create
        expect(WebMock).
          to_not have_requested(:post, "#{watched_repo_url}/pulls")
      end
    end

    context "with a custom footer" do
      subject(:creator) do
        Dependabot::PullRequestCreator.new(repo: repo,
                                           base_commit: base_commit,
                                           dependency: dependency,
                                           files: files,
                                           github_client: github_client,
                                           pr_message_footer: "Example text")
      end

      it "includes the custom text in the PR message" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/business-1.5.0",
              title: "Bump business from 1.4.0 to 1.5.0",
              body: /\n\nExample text/
            }
          )
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
      let(:gemfile_lock) do
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("ruby", "lockfiles", "Gemfile.lock"),
          directory: "directory"
        )
      end
      let(:branch_name) { "dependabot/bundler/directory/business-1.5.0" }

      it "includes the directory in the path of the files pushed to GitHub" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/trees").
          with(body: {
                 base_tree: "basecommitsha",
                 tree: [
                   {
                     path: "directory/Gemfile",
                     mode: "100644",
                     type: "blob",
                     content: fixture("ruby", "gemfiles", "Gemfile")
                   },
                   {
                     path: "directory/Gemfile.lock",
                     mode: "100644",
                     type: "blob",
                     content: fixture("ruby", "lockfiles", "Gemfile.lock")
                   }
                 ]
               })
      end

      it "includes the directory in the commit message" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/commits").
          with(body: {
                 parents: ["basecommitsha"],
                 tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
                 message: %r{Bump business from 1.4.0 to 1\.5\.0\ in /directory}
               })
      end

      it "includes the directory in the branch name" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/git/refs").
          with(body: {
                 ref: "refs/heads/dependabot/bundler/directory/business-1.5.0",
                 sha: "7638417db6d59f3c431d3e1f261cc637155684cd"
               })
      end

      it "includes the directory in the PR title" do
        creator.create

        expect(WebMock).
          to have_requested(:post, "#{watched_repo_url}/pulls").
          with(
            body: {
              base: "master",
              head: "dependabot/bundler/directory/business-1.5.0",
              title: "Bump business from 1.4.0 to 1.5.0 in /directory",
              body: "Bumps [business](https://github.com/gocardless/business) "\
                    "from 1.4.0 to 1.5.0.\n- [Release notes]"\
                    "(https://github.com/gocardless/business/releases?after="\
                    "v1.6.0)\n- [Changelog]"\
                    "(https://github.com/gocardless/business/blob/master"\
                    "/CHANGELOG.md)\n- [Commits]"\
                    "(https://github.com/gocardless/business/"\
                    "compare/v1.4.0...v1.5.0)"
            }
          )
      end
    end
  end
end
