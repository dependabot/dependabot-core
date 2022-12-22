# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
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
  let(:package_manager) { "dummy" }
  let(:dependency_name) { "business" }
  let(:dependency_version) { "1.4.0" }
  let(:dependency_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
  end
  let(:dependency_previous_version) { "1.0.0" }
  let(:credentials) { github_credentials }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/#{dependency_name}"
    )
  end
  before do
    stub_request(:get, service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end
  let(:service_pack_url) do
    "https://github.com/gocardless/business.git/info/refs" \
      "?service=git-upload-pack"
  end
  let(:upload_pack_fixture) { "business" }

  describe "#commits_url" do
    subject(:commits_url) { builder.commits_url }

    context "with a github repo and old/new tags" do
      let(:dependency_previous_version) { "1.3.0" }
      let(:upload_pack_fixture) { "business" }

      it do
        is_expected.to eq("https://github.com/gocardless/business/" \
                          "compare/v1.3.0...v1.4.0")
      end

      context "without a previous version" do
        let(:dependency_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.3.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_version) { nil }

        it do
          is_expected.to eq("https://github.com/gocardless/business/" \
                            "compare/v1.3.0...v1.4.0")
        end
      end
    end

    context "with a github repo and only a new tag" do
      let(:dependency_previous_version) { "0.1.0" }
      let(:upload_pack_fixture) { "business" }

      it do
        is_expected.
          to eq("https://github.com/gocardless/business/commits/v1.4.0")
      end

      context "and a directory" do
        before { source.directory = "my/directory" }

        it "doesn't include the directory (since it is unreliable)" do
          expect(commits_url).
            to eq("https://github.com/gocardless/business/commits/v1.4.0")
        end

        context "for a package manager with reliable source directories" do
          before do
            allow(builder).
              to receive(:reliable_source_directory?).
              and_return(true)
          end

          it "includes the directory" do
            expect(commits_url).
              to eq(
                "https://github.com/gocardless/business/commits/" \
                "v1.4.0/my/directory"
              )
          end

          context "when the directory starts with ./" do
            before { source.directory = "./my/directory" }

            it "joins the directory correctly" do
              expect(commits_url).
                to eq(
                  "https://github.com/gocardless/business/commits/" \
                  "v1.4.0/my/directory"
                )
            end
          end
        end
      end
    end

    context "with a github repo and tags with surprising names" do
      before do
        allow(builder).
          to receive(:fetch_dependency_tags).
          and_return(
            %w(
              business-1.4.0.beta
              business-21.4.0
              business-2.1.4.0
              business-1.4.-1
              business-1.4
              business-1.3.0
            )
          )
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/" \
                          "commits/business-1.4")
      end

      context "for a monorepo" do
        let(:dependency_name) { "@pollyjs/ember" }
        let(:dependency_version) { "0.2.0" }
        let(:dependency_previous_version) { "0.0.1" }
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "netflix/pollyjs",
            directory: "packages/ember"
          )
        end
        before do
          allow(builder).
            to receive(:fetch_dependency_tags).
            and_return(
              %w(
                @pollyjs/utils@0.1.0
                @pollyjs/persister@0.2.0
                @pollyjs/persister@0.1.0
                @pollyjs/node-server@0.2.0
                @pollyjs/node-server@0.1.0
                @pollyjs/node-server@0.0.2
                @pollyjs/node-server@0.0.1
                @pollyjs/ember-cli@0.2.1
                @pollyjs/ember-cli@0.2.0
                @pollyjs/ember-cli@0.1.0
                @pollyjs/ember-cli@0.0.2
                @pollyjs/ember-cli@0.0.1
                @pollyjs/ember@0.2.1
                @pollyjs/ember@0.2.0
                @pollyjs/ember@0.1.0
                @pollyjs/ember@0.0.2
                @pollyjs/ember@0.0.1
                @pollyjs/core@0.3.0
                @pollyjs/core@0.2.0
                @pollyjs/core@0.1.0
                @pollyjs/core@0.0.2
                @pollyjs/core@0.0.1
                @pollyjs/cli@0.1.1
                @pollyjs/cli@0.1.0
                @pollyjs/cli@0.0.2
                @pollyjs/cli@0.0.1
                @pollyjs/adapter@0.3.0
                @pollyjs/adapter@0.2.0
                @pollyjs/adapter@0.1.0
                @pollyjs/adapter@0.0.2
                @pollyjs/adapter@0.0.1
              )
            )
        end

        before do
          allow(builder).
            to receive(:reliable_source_directory?).
            and_return(true)
        end

        it do
          is_expected.to eq("https://github.com/netflix/pollyjs/" \
                            "commits/@pollyjs/ember@0.2.0/packages/ember")
        end

        context "without a previous version" do
          let(:dependency_previous_version) { "0.0.3" }

          it do
            is_expected.to eq("https://github.com/netflix/pollyjs/" \
                              "commits/@pollyjs/ember@0.2.0/packages/ember")
          end
        end

        context "without a non-correct previous version" do
          let(:dependency_previous_version) { "master" }

          it do
            is_expected.to eq("https://github.com/netflix/pollyjs/" \
                              "commits/@pollyjs/ember@0.2.0/packages/ember")
          end
        end
      end
    end

    context "with a github repo and tags with no prefix" do
      before do
        allow(builder).
          to receive(:fetch_dependency_tags).
          and_return(%w(1.5.0 1.4.0 1.3.0))
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/" \
                          "commits/1.4.0")
      end
    end

    context "with a github repo that has a DMCA takedown notice" do
      let(:url) { "https://github.com/gocardless/business.git" }
      before do
        stub_request(:get, service_pack_url).
          to_return(
            status: 503,
            body: fixture("github", "dmca_takedown.txt"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it { is_expected.to eq("https://github.com/gocardless/business/commits") }
    end

    context "with a github repo and no tags found" do
      let(:upload_pack_fixture) { "no_tags" }

      it do
        is_expected.to eq("https://github.com/gocardless/business/commits")
      end
    end

    context "with a dependency that has a git source" do
      let(:dependency_previous_requirements) do
        [{
          file: "Gemfile",
          requirement: ">= 0",
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/gocardless/business"
          }
        }]
      end
      let(:dependency_requirements) { dependency_previous_requirements }
      let(:dependency_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }
      let(:dependency_previous_version) do
        "7638417db6d59f3c431d3e1f261cc637155684cd"
      end

      it "uses the SHA-1 hashes to build the compare URL" do
        expect(builder.commits_url).
          to eq(
            "https://github.com/gocardless/business/compare/" \
            "7638417db6d59f3c431d3e1f261cc637155684cd..." \
            "cd8274d15fa3ae2ab983129fb037999f264ba9a7"
          )
      end

      context "with refs and numeric versions" do
        let(:dependency_version) { "1.4.0" }
        let(:dependency_previous_version) { "1.3.0" }
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: "v1.3.0"
            }
          }]
        end
        let(:dependency_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: "v1.4.0"
            }
          }]
        end

        it "uses the refs to build the compare URL" do
          expect(builder.commits_url).
            to eq(
              "https://github.com/gocardless/business/compare/v1.3.0...v1.4.0"
            )
        end
      end

      context "with multiple git sources", :vcr do
        let(:dependency_name) { "actions/checkout" }
        let(:dependency_version) { "aabbfeb2ce60b5bd82389903509092c4648a9713" }
        let(:dependency_previous_version) { nil }
        let(:source) do
          Dependabot::Source.new(provider: "github", repo: "actions/checkout")
        end
        let(:dependency_requirements) do
          [{
            file: ".github/workflows/workflow.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v2.2.0"
            },
            metadata: { declaration_string: "actions/checkout@v2.1.0" }
          }, {
            file: ".github/workflows/workflow.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v2.2.0"
            },
            metadata: { declaration_string: "actions/checkout@master" }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: ".github/workflows/workflow.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "v2.1.0"
            },
            metadata: { declaration_string: "actions/checkout@v2.1.0" }
          }, {
            file: ".github/workflows/workflow.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/actions/checkout",
              ref: "master"
            },
            metadata: { declaration_string: "actions/checkout@master" }
          }]
        end

        it "includes the commit in the commits URL" do
          expect(builder.commits_url).
            to eq(
              "https://github.com/actions/checkout/commits/" \
              "aabbfeb2ce60b5bd82389903509092c4648a9713"
            )
        end
      end

      context "when going from a git ref to a version requirement", :vcr do
        let(:dependency_name) { "business" }
        let(:dependency_version) { "1.8.0" }
        let(:dependency_previous_version) { nil }
        let(:dependency_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: [],
            source: nil
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: "v1.1.0"
            }
          }]
        end

        it "includes the previous ref and new version in the compare URL" do
          expect(builder.commits_url).
            to eq(
              "https://github.com/gocardless/business/compare/" \
              "v1.1.0...v1.8.0"
            )
        end
      end

      context "when going from a version requirement to a git ref", :vcr do
        let(:dependency_name) { "business" }
        let(:dependency_version) { "aabbfeb2ce60b5bd82389903509092c4648a9713" }
        let(:dependency_previous_version) { "1.1.0" }
        let(:dependency_requirements) do
          [{
            file: "Gemfile",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/gocardless/business",
              ref: "v1.8.0"
            }
          }]
        end
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: [],
            source: nil
          }]
        end

        it "includes the previous version and new commit in the compare URL" do
          expect(builder.commits_url).
            to eq(
              "https://github.com/gocardless/business/compare/" \
              "v1.1.0...aabbfeb2ce60b5bd82389903509092c4648a9713"
            )
        end
      end

      context "without a previous version" do
        let(:dependency_previous_version) { nil }

        it "uses the new SHA1 hash to build the compare URL" do
          expect(builder.commits_url).
            to eq("https://github.com/gocardless/business/commits/" \
                  "cd8274d15fa3ae2ab983129fb037999f264ba9a7")
        end
      end

      context "for the previous requirement only" do
        let(:dependency_requirements) do
          [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }]
        end
        let(:dependency_version) { "1.4.0" }
        let(:upload_pack_fixture) { "business" }

        it do
          is_expected.
            to eq("https://github.com/gocardless/business/compare/" \
                  "7638417db6d59f3c431d3e1f261cc637155684cd...v1.4.0")
        end

        context "without credentials" do
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
              stub_request(:get, service_pack_url).to_return(status: 404)

              url = "https://github.com/gocardless/business.git"
              exit_status = double(success?: false)
              allow(Open3).to receive(:capture3).and_call_original
              allow(Open3).to receive(:capture3).
                with(anything, "git ls-remote #{url}").
                and_return(["", "", exit_status])
            end

            it do
              is_expected.
                to eq("https://github.com/gocardless/business/commits")
            end
          end

          context "when authentication succeeds" do
            let(:upload_pack_fixture) { "business" }

            it do
              is_expected.
                to eq("https://github.com/gocardless/business/compare/" \
                      "7638417db6d59f3c431d3e1f261cc637155684cd...v1.4.0")
            end
          end
        end

        context "without a previous version" do
          let(:dependency_previous_version) { nil }

          it "uses the reference specified" do
            expect(builder.commits_url).
              to eq("https://github.com/gocardless/business/commits/v1.4.0")
          end

          context "but with a previously specified reference" do
            let(:dependency_previous_requirements) do
              [{
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  ref: "7638417"
                }
              }]
            end

            it "uses the reference specified" do
              # TODO: Figure out if we need to do a pinend? check here
              expect(builder.commits_url).
                to eq(
                  "https://github.com/gocardless/business/compare/" \
                  "7638417...v1.4.0"
                )
            end
          end
        end
      end
    end

    context "with a gitlab repo" do
      let(:service_pack_url) do
        "https://gitlab.com/org/business.git/info/refs" \
          "?service=git-upload-pack"
      end
      let(:gitlab_repo_url) do
        "https://gitlab.com/api/v4/projects/org%2Fbusiness"
      end

      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "org/#{dependency_name}"
        )
      end

      before do
        stub_request(:get, gitlab_repo_url).
          to_return(status: 200,
                    body: fixture("gitlab", "bump_repo.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://gitlab.com/org/business/" \
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
      let(:service_pack_url) do
        "https://bitbucket.org/org/business.git/info/refs" \
          "?service=git-upload-pack"
      end

      let(:source) do
        Dependabot::Source.new(
          provider: "bitbucket",
          repo: "org/#{dependency_name}"
        )
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
          builder.commits_url
          expect(WebMock).
            to have_requested(:get, service_pack_url).
            with(basic_auth: %w(greysteil secret_token))
        end
      end

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://bitbucket.org/org/business/" \
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

    context "with a azure repo" do
      let(:service_pack_url) do
        "https://dev.azure.com/contoso/MyProject/_git/business.git/info/refs" \
          "?service=git-upload-pack"
      end

      let(:source) do
        Dependabot::Source.new(
          provider: "azure",
          repo: "contoso/MyProject/_git/#{dependency_name}"
        )
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
          builder.commits_url
          expect(WebMock).
            to have_requested(:get, service_pack_url).
            with(basic_auth: %w(greysteil secret_token))
        end
      end

      context "with old and new tags" do
        let(:dependency_previous_version) { "1.3.0" }

        it "gets the right URL" do
          is_expected.to eq("https://dev.azure.com/contoso/MyProject/_git/business/" \
                            "branchCompare?baseVersion=GTv1.3.0&targetVersion=GTv1.4.0")
        end
      end

      context "with only a new tag" do
        let(:dependency_previous_version) { "0.3.0" }

        it "gets the right URL" do
          is_expected.
            to eq("https://dev.azure.com/contoso/MyProject/_git/business/commits?itemVersion=GTv1.4.0")
        end
      end

      context "with a dependency that has a git source" do
        let(:dependency_previous_requirements) do
          [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://dev.azure.com/contoso/MyProject/_git/#{dependency_name}"
            }
          }]
        end
        let(:dependency_requirements) { dependency_previous_requirements }

        context "with old and new sha" do
          let(:dependency_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }
          let(:dependency_previous_version) { "7638417db6d59f3c431d3e1f261cc637155684cd" }

          it "gets the right URL" do
            is_expected.to eq("https://dev.azure.com/contoso/MyProject/_git/business/" \
                              "branchCompare?baseVersion=GC7638417db6d59f3c431d3e1f261cc637155684cd" \
                              "&targetVersion=GCcd8274d15fa3ae2ab983129fb037999f264ba9a7")
          end
        end

        context "with only a new sha" do
          let(:dependency_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }
          let(:dependency_previous_version) { nil }

          it "gets the right URL" do
            is_expected.
              to eq("https://dev.azure.com/contoso/MyProject/_git/business/commits" \
                    "?itemVersion=GCcd8274d15fa3ae2ab983129fb037999f264ba9a7")
          end
        end
      end

      context "no tags" do
        let(:dependency_previous_version) { "0.3.0" }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://dev.azure.com/contoso/MyProject/_git/business/commits")
        end
      end

      context "no previous version" do
        let(:dependency_previous_version) { nil }
        let(:dependency_version) { "0.5.0" }

        it "gets the right URL" do
          is_expected.to eq("https://dev.azure.com/contoso/MyProject/_git/business/commits")
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
            "https://api.github.com/repos/gocardless/business/commits?" \
            "sha=v1.3.0"
          ).to_return(
            status: 200,
            body: fixture("github", "commits-business-1.3.0.json"),
            headers: { "Content-Type" => "application/json" }
          )
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/commits?" \
            "sha=v1.4.0"
          ).to_return(
            status: 200,
            body: fixture("github", "commits-business-1.4.0.json"),
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "returns an array of commits" do
          is_expected.to eq(
            [
              {
                message: "[12]() Remove _SEPA_ calendar (replaced by TARGET)",
                sha: "d2eb29beda934c14220146c82f830de2edd63a25",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "d2eb29beda934c14220146c82f830de2edd63a25"
              },
              {
                message: "Merge pull request #8 from gocardless/" \
                         "rename-sepa-to-ecb\n\nRemove _SEPA_ calendar " \
                         "(replaced by TARGET)",
                sha: "a5970daf0b824e4c3974e57474b6cf9e39a11d0f",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "a5970daf0b824e4c3974e57474b6cf9e39a11d0f"
              },
              {
                message: "Spacing: https://github.com/my/repo/pull/5",
                sha: "0bfb8c3f0d2701abf9248185beeb8adf643374f6",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "0bfb8c3f0d2701abf9248185beeb8adf643374f6"
              },
              {
                message: "\n",
                sha: "5555535ff2aa9d7ce0403d7fd4aa010d94723076",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "5555535ff2aa9d7ce0403d7fd4aa010d94723076"
              },
              {
                message: "Allow custom calendars",
                sha: "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076"
              },
              {
                message: "[Fix #9] Allow custom calendars",
                sha: "7abe4c2dc0161904c40c221a48999d12995fbea7",
                html_url: "https://github.com/gocardless/business/commit/" \
                          "7abe4c2dc0161904c40c221a48999d12995fbea7"
              },
              {
                message: "Bump version to v1.4.0",
                sha: "26f4887ec647493f044836363537e329d9d213aa",
                html_url: "https://github.com/gocardless/business/commit/" \
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
              "https://api.github.com/repos/gocardless/business/commits?" \
              "sha=v1.3.0"
            ).to_return(
              status: 404,
              body: response,
              headers: { "Content-Type" => "application/json" }
            )
          end

          it { is_expected.to eq([]) }
        end

        context "for a monorepo" do
          let(:dependency_name) { "@pollyjs/ember" }
          let(:dependency_version) { "0.2.0" }
          let(:dependency_previous_version) { "0.1.0" }
          let(:source) do
            Dependabot::Source.new(
              provider: "github",
              repo: "netflix/pollyjs",
              directory: "packages/@pollyjs/ember"
            )
          end
          before do
            allow(builder).
              to receive(:fetch_dependency_tags).
              and_return(
                %w(
                  @pollyjs/ember-cli@0.2.1
                  @pollyjs/ember-cli@0.2.0
                  @pollyjs/ember-cli@0.1.0
                  @pollyjs/ember-cli@0.0.2
                  @pollyjs/ember-cli@0.0.1
                  @pollyjs/ember@0.2.1
                  @pollyjs/ember@0.2.0
                  @pollyjs/ember@0.1.0
                  @pollyjs/ember@0.0.2
                  @pollyjs/ember@0.0.1
                )
              )
          end

          before do
            allow(builder).
              to receive(:reliable_source_directory?).
              and_return(true)
          end

          before do
            stub_request(
              :get,
              "https://api.github.com/repos/netflix/pollyjs/commits?" \
              "path=packages/@pollyjs/ember&sha=@pollyjs/ember@0.2.0"
            ).to_return(
              status: 200,
              body: fixture("github", "commits-pollyjs-ember-0.2.0.json"),
              headers: { "Content-Type" => "application/json" }
            )

            stub_request(
              :get,
              "https://api.github.com/repos/netflix/pollyjs/commits?" \
              "path=packages/@pollyjs/ember&sha=@pollyjs/ember@0.1.0"
            ).to_return(
              status: 200,
              body: fixture("github", "commits-pollyjs-ember-0.1.0.json"),
              headers: { "Content-Type" => "application/json" }
            )
          end

          it "returns an array of commits relevant to the given path" do
            is_expected.to match_array(
              [
                {
                  message: "feat: Custom persister support\n\n" \
                           "* feat: Custom persister support\r\n\r\n" \
                           "* Create a @pollyjs/persister package\r\n" \
                           "* Move out shared utils into their own " \
                           "@pollyjs/utils package\r\n" \
                           "* Add support to register a custom persister " \
                           "(same way as an adapter)\r\n" \
                           "* Add more tests\r\n\r\n" \
                           "* docs: Custom adapter & persister docs\r\n\r\n" \
                           "* test: Add custom persister test",
                  sha: "8bb313cc08716b80076c6f68d056396ce4b4d282",
                  html_url: "https://github.com/Netflix/pollyjs/commit/" \
                            "8bb313cc08716b80076c6f68d056396ce4b4d282"
                },
                {
                  message: "chore: Publish\n\n" \
                           " - @pollyjs/adapter@0.2.0\n" \
                           " - @pollyjs/core@0.2.0\n" \
                           " - @pollyjs/ember@0.2.0\n" \
                           " - @pollyjs/persister@0.1.0\n" \
                           " - @pollyjs/utils@0.1.0",
                  sha: "ebf6474d0008e9e76249a78473263894dd0668dc",
                  html_url: "https://github.com/Netflix/pollyjs/commit/" \
                            "ebf6474d0008e9e76249a78473263894dd0668dc"
                }
              ]
            )
          end
        end
      end

      context "with a bitbucket repo" do
        let(:bitbucket_compare_url) do
          "https://api.bitbucket.org/2.0/repositories/org/business/commits/" \
            "?exclude=v1.3.0&include=v1.4.0"
        end

        let(:bitbucket_compare) do
          fixture("bitbucket", "business_compare_commits.json")
        end

        let(:source) do
          Dependabot::Source.new(
            provider: "bitbucket",
            repo: "org/#{dependency_name}"
          )
        end
        let(:service_pack_url) do
          "https://bitbucket.org/org/business.git/info/refs" \
            "?service=git-upload-pack"
        end

        before do
          stub_request(:get, bitbucket_compare_url).
            to_return(status: 200,
                      body: bitbucket_compare,
                      headers: { "Content-Type" => "application/json" })
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message: "Added signature for changeset f275e318641f",
                sha: "deae742eacfa985bd20f47a12a8fee6ce2e0447c",
                html_url: "https://bitbucket.org/ged/ruby-pg/commits/" \
                          "deae742eacfa985bd20f47a12a8fee6ce2e0447c"
              },
              {
                message: "Eliminate use of deprecated PGError constant from " \
                         "specs",
                sha: "f275e318641f185b8a15a2220e7c189b1769f84c",
                html_url: "https://bitbucket.org/ged/ruby-pg/commits/" \
                          "f275e318641f185b8a15a2220e7c189b1769f84c"
              }
            ]
          )
        end
      end

      context "with a azure repo" do
        let(:azure_compare_url) do
          "https://dev.azure.com/contoso/MyProject/_apis/git/repositories/business/commits" \
            "?searchCriteria.itemVersion.versionType=tag" \
            "&searchCriteria.itemVersion.version=v1.3.0" \
            "&searchCriteria.compareVersion.versionType=tag" \
            "&searchCriteria.compareVersion.version=v1.4.0"
        end

        let(:azure_compare) do
          fixture("azure", "business_compare_commits.json")
        end

        let(:source) do
          Dependabot::Source.new(
            provider: "azure",
            repo: "contoso/MyProject/_git/#{dependency_name}"
          )
        end
        let(:service_pack_url) do
          "https://dev.azure.com/contoso/MyProject/_git/business.git/info/refs" \
            "?service=git-upload-pack"
        end

        before do
          stub_request(:get, azure_compare_url).
            to_return(status: 200,
                      body: azure_compare,
                      headers: { "Content-Type" => "application/json" })
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message: "Merged PR 2: Deleted README.md",
                sha: "9991b4f66def4c0a9ad8f9f27043ece7eddcf1c7",
                html_url: "https://dev.azure.com/fabrikam/SomeGitProject/_git/SampleRepository/commit/" \
                          "9991b4f66def4c0a9ad8f9f27043ece7eddcf1c7"
              },
              {
                message: "Added README.md file",
                sha: "4fa42e1a7b0215cc70cd4e927cb70c422123af84",
                html_url: "https://dev.azure.com/fabrikam/SomeGitProject/_git/SampleRepository/commit/" \
                          "4fa42e1a7b0215cc70cd4e927cb70c422123af84"
              }
            ]
          )
        end

        context "with a dependency that has a git source" do
          let(:dependency_previous_requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://dev.azure.com/contoso/MyProject/_git/#{dependency_name}"
              }
            }]
          end
          let(:dependency_requirements) { dependency_previous_requirements }
          let(:dependency_version) { "cd8274d15fa3ae2ab983129fb037999f264ba9a7" }
          let(:dependency_previous_version) { "7638417db6d59f3c431d3e1f261cc637155684cd" }
          let(:azure_compare_url) do
            "https://dev.azure.com/contoso/MyProject/_apis/git/repositories/business/commits" \
              "?searchCriteria.itemVersion.versionType=commit" \
              "&searchCriteria.itemVersion.version=7638417db6d59f3c431d3e1f261cc637155684cd" \
              "&searchCriteria.compareVersion.versionType=commit" \
              "&searchCriteria.compareVersion.version=cd8274d15fa3ae2ab983129fb037999f264ba9a7"
          end

          it "returns an array of commits" do
            is_expected.to match_array(
              [
                {
                  message: "Merged PR 2: Deleted README.md",
                  sha: "9991b4f66def4c0a9ad8f9f27043ece7eddcf1c7",
                  html_url: "https://dev.azure.com/fabrikam/SomeGitProject/_git/SampleRepository/commit/" \
                            "9991b4f66def4c0a9ad8f9f27043ece7eddcf1c7"
                },
                {
                  message: "Added README.md file",
                  sha: "4fa42e1a7b0215cc70cd4e927cb70c422123af84",
                  html_url: "https://dev.azure.com/fabrikam/SomeGitProject/_git/SampleRepository/commit/" \
                            "4fa42e1a7b0215cc70cd4e927cb70c422123af84"
                }
              ]
            )
          end

          context "that 404s" do
            before do
              response = { message: "404 Project Not Found" }.to_json
              stub_request(:get, azure_compare_url).
                to_return(status: 404,
                          body: response,
                          headers: { "Content-Type" => "application/json" })
            end

            it { is_expected.to eq([]) }
          end
        end
      end

      context "with a gitlab repo" do
        let(:gitlab_compare_url) do
          "https://gitlab.com/api/v4/projects/org%2Fbusiness/repository/" \
            "compare?from=v1.3.0&to=v1.4.0"
        end
        let(:service_pack_url) do
          "https://gitlab.com/org/business.git/info/refs" \
            "?service=git-upload-pack"
        end

        let(:gitlab_compare) do
          fixture("gitlab", "business_compare_commits.json")
        end
        let(:source) do
          Dependabot::Source.new(
            provider: "gitlab",
            repo: "org/#{dependency_name}"
          )
        end
        before do
          stub_request(:get, gitlab_compare_url).
            to_return(status: 200,
                      body: gitlab_compare,
                      headers: { "Content-Type" => "application/json" })
        end

        it "returns an array of commits" do
          is_expected.to match_array(
            [
              {
                message: "Add find command\n",
                sha: "8d7d08fb9a7a439b3e6a1e6a1a34cbdb4273de87",
                html_url: "https://gitlab.com/org/business/commit/" \
                          "8d7d08fb9a7a439b3e6a1e6a1a34cbdb4273de87"
              },
              {
                message: "...\n",
                sha: "4ac81646582f254b3e86653b8fcd5eda6d8bb45d",
                html_url: "https://gitlab.com/org/business/commit/" \
                          "4ac81646582f254b3e86653b8fcd5eda6d8bb45d"
              },
              {
                message: "MP version\n",
                sha: "4e5081f867631f10d8a29dc6853a052f52241fab",
                html_url: "https://gitlab.com/org/business/commit/" \
                          "4e5081f867631f10d8a29dc6853a052f52241fab"
              },
              {
                message: "BUG: added 'force_consistent' keyword argument " \
                         "with default True\n\nThe bug fix is necessary to " \
                         "pass the test turbomole_h3o2m.py.\n",
                sha: "e718899ddcdc666311d08497401199e126428163",
                html_url: "https://gitlab.com/org/business/commit/" \
                          "e718899ddcdc666311d08497401199e126428163"
              }
            ]
          )
        end

        context "with a dependency that has a git source" do
          let(:dependency_previous_requirements) do
            [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://gitlab.com/orgs/#{dependency_name}"
              }
            }]
          end
          let(:dependency_requirements) { dependency_previous_requirements }
          let(:dependency_version) do
            "cd8274d15fa3ae2ab983129fb037999f264ba9a7"
          end
          let(:dependency_previous_version) do
            "7638417db6d59f3c431d3e1f261cc637155684cd"
          end

          context "that 404s" do
            before do
              response = { message: "404 Project Not Found" }.to_json
              gitlab_compare_url =
                "https://gitlab.com/api/v4/projects/" \
                "org%2Fbusiness/repository/compare" \
                "?from=7638417db6d59f3c431d3e1f261cc637155684cd" \
                "&to=cd8274d15fa3ae2ab983129fb037999f264ba9a7"
              stub_request(:get, gitlab_compare_url).
                to_return(status: 404,
                          body: response,
                          headers: { "Content-Type" => "application/json" })
            end

            it { is_expected.to eq([]) }
          end
        end
      end
    end

    context "with only a new tag" do
      let(:dependency_previous_version) { "0.1.0" }
      let(:upload_pack_fixture) { "business" }

      it { is_expected.to eq([]) }
    end

    context "with no tags found" do
      let(:upload_pack_fixture) { "no_tags" }

      it { is_expected.to eq([]) }
    end

    context "without a recognised source" do
      let(:source) { nil }
      it { is_expected.to eq([]) }
    end
  end
end
