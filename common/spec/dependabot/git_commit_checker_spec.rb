# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_commit_checker"

RSpec.describe Dependabot::GitCommitChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: version,
      requirements: requirements,
      package_manager: "dummy"
    )
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }

  let(:requirements) do
    [{ file: "Gemfile", requirement: ">= 0", groups: [], source: source }]
  end

  let(:source) do
    {
      type: "git",
      url: "https://github.com/gocardless/business",
      branch: "master",
      ref: "master"
    }
  end

  let(:version) { "df9f605d7111b6814fe493cf8f41de3f9f0978b2" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }, {
      "some" => "irrelevant credential"
    }]
  end

  describe "#git_dependency?" do
    subject { checker.git_dependency? }

    context "with a non-git dependency" do
      let(:source) { nil }
      it { is_expected.to eq(false) }
    end

    context "with a non-git dependency that has multiple sources" do
      let(:requirements) do
        [
          {
            file: "package.json",
            requirement: "0.1.0",
            groups: ["dependencies"],
            source: { type: "registry", url: "https://registry.npmjs.org" }
          },
          {
            file: "package.json",
            requirement: "0.1.0",
            groups: ["devDependencies"],
            source: { type: "registry", url: "https://registry.yarnpkg.com" }
          }
        ]
      end

      it { is_expected.to eq(false) }
    end

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: nil,
          ref: nil
        }
      end

      it { is_expected.to eq(true) }

      context "hosted on bitbucket" do
        let(:source) do
          {
            type: "git",
            url: "https://bitbucket.org/gocardless/business",
            branch: nil,
            ref: nil
          }
        end

        it { is_expected.to eq(true) }
      end

      context "with multiple sources" do
        let(:requirements) do
          [
            { file: "Gemfile", requirement: ">= 0", groups: [], source: s1 },
            { file: "Gemfile", requirement: ">= 0", groups: [], source: s2 }
          ]
        end

        let(:s1) { source }

        context "both of which are git, with the same URL" do
          let(:s2) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: nil,
              ref: nil
            }
          end

          it { is_expected.to eq(true) }
        end

        context "with multiple source types" do
          let(:s2) { { type: "git", url: "https://github.com/dependabot/dependabot-core" } }

          it "raises a helpful error" do
            expect { checker.git_dependency? }.
              to raise_error(/Multiple sources!/)
          end
        end
      end
    end
  end

  describe "#branch_or_ref_in_release?" do
    subject { checker.branch_or_ref_in_release?(Gem::Version.new("1.5.0")) }

    context "with a non-git dependency" do
      let(:source) { nil }
      specify { expect { subject }.to raise_error(/Not a git dependency!/) }
    end

    context "with a git dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "df9f605"
        }
      end

      context "when the source code can't be found" do
        before do
          allow_any_instance_of(DummyPackageManager::MetadataFinder).
            to receive(:look_up_source).and_return(nil)
        end

        it { is_expected.to eq(false) }
      end

      context "with source code hosted on GitHub" do
        let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
        let(:service_pack_url) do
          "https://github.com/gocardless/business.git/info/refs" \
            "?service=git-upload-pack"
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
        let(:upload_pack_fixture) { "no_tags" }

        context "but no tags on GitHub" do
          let(:upload_pack_fixture) { "no_tags" }
          it { is_expected.to eq(false) }
        end

        context "but GitHub returns a 404" do
          let(:url) { "https://github.com/gocardless/business.git" }

          before do
            stub_request(:get, service_pack_url).to_return(status: 404)

            exit_status = double(success?: false)
            allow(Open3).to receive(:capture3).and_call_original
            allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
          end

          it { is_expected.to eq(false) }
        end

        context "with tags on GitHub" do
          let(:upload_pack_fixture) { "business" }
          let(:comparison_url) { repo_url + "/compare/v1.5.0...df9f605" }
          before do
            stub_request(:get, comparison_url).
              to_return(
                status: 200,
                body: comparison_response,
                headers: { "Content-Type" => "application/json" }
              )
          end

          context "when the specified reference is not in the release" do
            let(:comparison_response) do
              fixture("github", "commit_compare_diverged.json")
            end
            it { is_expected.to eq(false) }
          end

          context "when the specified reference is included in the release" do
            let(:comparison_response) do
              fixture("github", "commit_compare_behind.json")
            end
            it { is_expected.to eq(true) }

            context "even though this fork is not on GitHub" do
              let(:source) do
                {
                  type: "git",
                  url: "https://bitbucket.org/gocardless/business",
                  branch: "master",
                  ref: "df9f605"
                }
              end
              it { is_expected.to eq(true) }
            end

            context "when there is no github.com credential" do
              let(:credentials) do
                [{
                  "type" => "git_source",
                  "host" => "bitbucket.org",
                  "username" => "x-access-token",
                  "password" => "token"
                }]
              end
              it { is_expected.to eq(true) }
            end
          end

          context "with an unpinned dependency" do
            let(:source) do
              {
                type: "git",
                url: "https://github.com/gocardless/business",
                branch: branch,
                ref: nil
              }
            end
            let(:branch) { "master" }
            let(:comparison_url) { repo_url + "/compare/v1.5.0...master" }
            let(:comparison_response) do
              fixture("github", "commit_compare_behind.json")
            end

            it { is_expected.to eq(true) }

            context "that has no branch specified" do
              let(:branch) { nil }
              let(:comparison_url) { "unused" }
              let(:comparison_response) { "unused" }

              it { is_expected.to eq(false) }
            end
          end
        end
      end

      context "with source code not hosted on GitHub" do
        before do
          allow_any_instance_of(DummyPackageManager::MetadataFinder).
            to receive(:look_up_source).
            and_return(Dependabot::Source.from_url(source_url))
        end
        let(:source_url) { "https://bitbucket.org/gocardless/business" }
        let(:service_pack_url) do
          "https://bitbucket.org/gocardless/business.git/info/refs" \
            "?service=git-upload-pack"
        end
        let(:bitbucket_url) do
          "https://api.bitbucket.org/2.0/repositories/" \
            "gocardless/business/commits/?exclude=v1.5.0&include=df9f605"
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
        let(:upload_pack_fixture) { "business" }

        context "when not included in a release" do
          before do
            stub_request(:get, bitbucket_url).
              to_return(
                status: 200,
                body: fixture("bitbucket", "business_compare_commits.json"),
                headers: { "Content-Type" => "application/json" }
              )
          end

          it { is_expected.to eq(false) }
        end

        context "when bitbucket 404s" do
          before do
            stub_request(:get, bitbucket_url).
              to_return(
                status: 404,
                body: { "type" => "error" }.to_json,
                headers: { "Content-Type" => "application/json" }
              )
          end

          it { is_expected.to eq(false) }
        end

        context "when bitbucket 404s" do
          before do
            stub_request(:get, bitbucket_url).
              to_return(
                status: 200,
                body: { "pagelen" => 30, "values" => [] }.to_json,
                headers: { "Content-Type" => "application/json" }
              )
          end

          it { is_expected.to eq(true) }
        end
      end
    end
  end

  describe "#pinned?" do
    subject { checker.pinned? }

    let(:source) do
      {
        type: "git",
        url: "https://github.com/gocardless/business",
        branch: branch,
        ref: ref
      }
    end

    context "with a non-git dependency" do
      let(:source) { nil }
      specify { expect { subject }.to raise_error(/Not a git dependency!/) }
    end

    context "with no branch or reference specified" do
      let(:ref) { nil }
      let(:branch) { nil }
      it { is_expected.to eq(false) }
    end

    context "with no reference specified" do
      let(:ref) { nil }
      let(:branch) { "master" }
      it { is_expected.to eq(false) }
    end

    context "with a reference that matches the branch" do
      let(:ref) { "master" }
      let(:branch) { "master" }
      it { is_expected.to eq(false) }
    end

    context "with a reference that does not match the branch" do
      let(:ref) { "v1.0.0" }
      let(:branch) { "master" }
      it { is_expected.to eq(true) }
    end

    context "with no branch specified" do
      let(:branch) { nil }

      context "and a reference that matches the version" do
        let(:ref) { "df9f605" }
        it { is_expected.to eq(true) }
      end

      context "and a reference that does not match the version" do
        let(:repo_url) { "https://github.com/gocardless/business.git" }
        before do
          stub_request(:get, repo_url + "/info/refs?service=git-upload-pack").
            to_return(
              status: 200,
              body: fixture("git", "upload_packs", "manifesto"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        context "and does not match any branch names" do
          let(:ref) { "my_ref" }
          it { is_expected.to eq(true) }
        end

        context "and does match a branch names" do
          let(:ref) { "master" }
          it { is_expected.to eq(false) }
        end

        context "with a bitbucket source" do
          let(:source) do
            {
              type: "git",
              url: "https://bitbucket.org/gocardless/business",
              branch: branch,
              ref: ref
            }
          end
          let(:repo_url) { "https://bitbucket.org/gocardless/business.git" }

          let(:ref) { "my_ref" }
          it { is_expected.to eq(true) }
        end

        context "when the source is unreachable" do
          before do
            git_url = "https://github.com/gocardless/business.git"
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_return(status: 404)

            exit_status = double(success?: false)
            allow(Open3).to receive(:capture3).and_call_original
            allow(Open3).to receive(:capture3).
              with(anything, "git ls-remote #{git_url}").
              and_return(["", "", exit_status])
          end
          let(:ref) { "my_ref" }

          it "raises a helpful error" do
            expect { checker.head_commit_for_current_branch }.
              to raise_error(Dependabot::GitDependenciesNotReachable)
          end
        end

        context "when the source returns a timeout" do
          context "and is unknown" do
            let(:source) do
              {
                type: "git",
                url: "https://dodgyhost.com/gocardless/business",
                branch: "master",
                ref: "master"
              }
            end
            before do
              url = "https://dodgyhost.com/gocardless/business.git"
              stub_request(:get, url + "/info/refs?service=git-upload-pack").
                to_raise(Excon::Error::Timeout)
            end
            let(:ref) { "my_ref" }

            it "raises a helpful error" do
              expect { checker.head_commit_for_current_branch }.
                to raise_error(Dependabot::GitDependenciesNotReachable)
            end
          end

          context "but is GitHub" do
            before do
              url = "https://github.com/gocardless/business.git"
              stub_request(:get, url + "/info/refs?service=git-upload-pack").
                to_raise(Excon::Error::Timeout)
            end
            let(:ref) { "my_ref" }

            it "raises a generic error (that won't be misinterpreted)" do
              expect { checker.head_commit_for_current_branch }.
                to raise_error(Excon::Error::Timeout)
            end
          end
        end
      end
    end
  end

  describe "#head_commit_for_current_branch" do
    subject { checker.head_commit_for_current_branch }

    context "with a pinned dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "v1.0.0"
        }
      end

      let(:git_header) do
        { "content-type" => "application/x-git-upload-pack-advertisement" }
      end
      let(:auth_header) { "Basic eC1hY2Nlc3MtdG9rZW46dG9rZW4=" }

      let(:git_url) do
        "https://github.com/gocardless/business.git" \
          "/info/refs?service=git-upload-pack"
      end

      context "that can be reached just fine" do
        before do
          stub_request(:get, git_url).
            with(headers: { "Authorization" => auth_header }).
            to_return(
              status: 200,
              body: fixture("git", "upload_packs", "business"),
              headers: git_header
            )
        end

        it { is_expected.to eq(dependency.version) }

        context "without a version" do
          let(:version) { nil }

          it { is_expected.to eq("df9f605d7111b6814fe493cf8f41de3f9f0978b2") }

          context "but doesn't have details of the current branch" do
            before { source.merge!(ref: "rando") }

            it { is_expected.to be_nil }
          end
        end
      end
    end

    context "with a non-pinned dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "master"
        }
      end
      let(:git_header) do
        { "content-type" => "application/x-git-upload-pack-advertisement" }
      end
      let(:auth_header) { "Basic eC1hY2Nlc3MtdG9rZW46dG9rZW4=" }

      let(:git_url) do
        "https://github.com/gocardless/business.git" \
          "/info/refs?service=git-upload-pack"
      end

      context "that can be reached just fine" do
        before do
          stub_request(:get, git_url).
            with(headers: { "Authorization" => auth_header }).
            to_return(
              status: 200,
              body: fixture("git", "upload_packs", "business"),
              headers: git_header
            )
        end

        it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }

        context "with no branch specified" do
          let(:source) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: nil,
              ref: nil
            }
          end

          it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }
        end

        context "with a symref specified" do
          before do
            stub_request(:get, git_url).
              with(headers: { "Authorization" => auth_header }).
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "sym-linked"),
                headers: git_header
              )
          end

          it { is_expected.to eq("c01b0c78663a92f5cb7057cc92f910919f4085fc") }

          context "with no branch specified" do
            let(:source) do
              {
                type: "git",
                url: "https://github.com/gocardless/business",
                branch: nil,
                ref: nil
              }
            end

            it { is_expected.to eq("c01b0c78663a92f5cb7057cc92f910919f4085fc") }
          end
        end

        context "specified with an SSH URL" do
          before { source.merge!(url: "git@github.com:gocardless/business") }

          it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }
        end

        context "specified with a git URL" do
          before do
            source.merge!(url: "git://github.com/gocardless/business.git")
          end

          it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }
        end

        context "but doesn't have details of the current branch" do
          before { source.merge!(branch: "rando", ref: "rando") }

          it "raises a helpful error" do
            expect { checker.head_commit_for_current_branch }.
              to raise_error(Dependabot::GitDependencyReferenceNotFound)
          end
        end
      end

      context "that results in a 403" do
        let(:url) { "https://github.com/gocardless/business.git" }

        before do
          stub_request(:get, git_url).
            with(headers: { "Authorization" => auth_header }).
            to_return(status: 403)

          exit_status = double(success?: false)
          allow(Open3).to receive(:capture3).and_call_original
          allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
        end

        it "raises a helpful error" do
          expect { checker.head_commit_for_current_branch }.
            to raise_error(Dependabot::GitDependenciesNotReachable)
        end
      end

      context "with a bitbucket source" do
        let(:source) do
          {
            type: "git",
            url: "https://bitbucket.org/gocardless/business",
            branch: "master",
            ref: "master"
          }
        end
        let(:git_url) do
          "https://bitbucket.org/gocardless/business.git" \
            "/info/refs?service=git-upload-pack"
        end

        context "that needs credentials to succeed" do
          before do
            stub_request(:get, git_url).to_return(status: 403)
            stub_request(:get, git_url).
              with(headers: { "Authorization" => auth_header }).
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "business"),
                headers: git_header
              )
          end

          context "and doesn't have them" do
            it "raises a helpful error" do
              expect { checker.head_commit_for_current_branch }.
                to raise_error(Dependabot::GitDependenciesNotReachable)
            end
          end

          context "and has them" do
            let(:credentials) do
              [{
                "type" => "git_source",
                "host" => "bitbucket.org",
                "username" => "x-access-token",
                "password" => "token"
              }]
            end

            it { is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104") }

            context "already encoded in the URL" do
              let(:source) do
                {
                  type: "git",
                  url: "https://x-access-token:token@bitbucket.org/gocardless/" \
                       "business",
                  branch: "master",
                  ref: "master"
                }
              end

              it do
                is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104")
              end
            end
          end
        end
      end
    end
  end

  describe "#pinned_ref_looks_like_version?" do
    subject { checker.pinned_ref_looks_like_version? }

    context "with a non-pinned dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "master"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with a version pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "v1.0.0"
        }
      end
      it { is_expected.to eq(true) }

      context "that includes a hyphen" do
        let(:source) do
          {
            type: "git",
            url: "https://github.com/gocardless/business",
            branch: "master",
            ref: "v1.0.0-pre"
          }
        end
        it { is_expected.to eq(true) }
      end

      context "that is just v1" do
        let(:source) do
          {
            type: "git",
            url: "https://github.com/gocardless/business",
            branch: "master",
            ref: "v1"
          }
        end
        it { is_expected.to eq(true) }
      end
    end

    context "with a non-version pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "1a21311"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with no ref" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: nil
        }
      end
      it { is_expected.to eq(false) }
    end
  end

  describe "#pinned_ref_looks_like_commit_sha?" do
    subject { checker.pinned_ref_looks_like_commit_sha? }

    context "with a non-pinned dependency" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "master"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with a version pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "v1.0.0"
        }
      end
      it { is_expected.to eq(false) }
    end

    context "with a git commit pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "1a21311"
        }
      end

      let(:repo_url) { "https://github.com/gocardless/business.git" }
      let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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
      let(:upload_pack_fixture) { "monolog" }

      it { is_expected.to eq(true) }

      context "that matches a tag" do
        let(:source) do
          {
            type: "git",
            url: "https://github.com/gocardless/business",
            branch: "master",
            ref: "aaaaaaaa"
          }
        end

        it { is_expected.to eq(false) }
      end
    end

    context "with no ref" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: nil
        }
      end
      it { is_expected.to eq(false) }
    end
  end

  describe "#head_commit_for_local_branch" do
    let(:tip_of_example) { "303b8a83c87d5c6d749926cf02620465a5dcd0f2" }

    subject { checker.head_commit_for_local_branch("example") }

    let(:repo_url) { "https://github.com/gocardless/business.git" }
    let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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

    let(:upload_pack_fixture) { "monolog" }

    it { is_expected.to eq(tip_of_example) }
  end

  describe "#local_tag_for_latest_version" do
    subject { checker.local_tag_for_latest_version }
    let(:repo_url) { "https://github.com/gocardless/business.git" }
    let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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
    let(:upload_pack_fixture) { "no_tags" }

    context "with no tags on GitHub" do
      it { is_expected.to eq(nil) }
    end

    context "but GitHub returns a 404" do
      let(:url) { "https://github.com/gocardless/business.git" }

      before do
        stub_request(:get, service_pack_url).to_return(status: 404)

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it "raises a helpful error" do
        expect { checker.local_tag_for_latest_version }.
          to raise_error(Dependabot::GitDependenciesNotReachable)
      end
    end

    context "with tags on GitHub" do
      context "but no version tags" do
        let(:upload_pack_fixture) { "no_versions" }
        it { is_expected.to eq(nil) }
      end

      context "with version tags" do
        let(:upload_pack_fixture) { "business" }

        its([:tag]) { is_expected.to eq("v1.13.0") }
        its([:commit_sha]) do
          is_expected.to eq("7bb4e41ce5164074a0920d5b5770d196b4d90104")
        end
        its([:tag_sha]) do
          is_expected.to eq("37f41032a0f191507903ebbae8a5c0cb945d7585")
        end

        context "and a pre-release latest version" do
          let(:upload_pack_fixture) { "k8s-apiextensions-apiserver" }
          its([:tag]) { is_expected.to eq("kubernetes-1.11.2") }

          context "when using a pre-release" do
            let(:source) do
              {
                type: "git",
                url: "https://github.com/gocardless/business",
                branch: "master",
                ref: "kubernetes-1.11.3-beta.0"
              }
            end

            its([:tag]) { is_expected.to eq("kubernetes-1.13.0-alpha.0") }
          end
        end

        context "and a monorepo using prefixed tags" do
          let(:upload_pack_fixture) { "gatsby" }
          let(:source) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: "master",
              ref: "gatsby-transformer-sqip@2.0.39"
            }
          end

          its([:tag]) { is_expected.to eq("gatsby-transformer-sqip@2.0.40") }
        end

        context "raise_on_ignored when later versions are allowed" do
          let(:raise_on_ignored) { true }
          it "doesn't raise an error" do
            expect { subject }.to_not raise_error
          end
        end

        context "already on the latest version" do
          let(:version) { "1.13.0" }
          its([:tag]) { is_expected.to eq("v1.13.0") }

          context "raise_on_ignored" do
            let(:raise_on_ignored) { true }
            it "doesn't raise an error" do
              expect { subject }.to_not raise_error
            end
          end
        end

        context "all later versions ignored" do
          let(:version) { "1.0.0" }
          let(:ignored_versions) { ["> 1.0.0"] }
          its([:tag]) { is_expected.to eq("v1.0.0") }

          context "raise_on_ignored" do
            let(:raise_on_ignored) { true }
            it "raises an error" do
              expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
            end
          end
        end

        context "and an ignore condition" do
          let(:ignored_versions) { [">= 1.12.0"] }
          its([:tag]) { is_expected.to eq("v1.11.1") }
        end

        context "multiple ignore conditions" do
          let(:ignored_versions) { [">= 1.11.2, < 1.12.0"] }
          its([:tag]) { is_expected.to eq("v1.13.0") }
        end

        context "all versions ignored" do
          let(:ignored_versions) { [">= 0"] }
          it "returns nil" do
            expect(subject).to be_nil
          end

          context "raise_on_ignored" do
            let(:raise_on_ignored) { true }
            it "raises an error" do
              expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
            end
          end
        end

        context "and a ref prefixed with tags/" do
          let(:source) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: "master",
              ref: "tags/1.2.0"
            }
          end

          its([:tag]) { is_expected.to eq("tags/v1.13.0") }
        end
      end
    end
  end

  describe "#local_ref_for_latest_version_matching_existing_precision" do
    subject { checker.local_ref_for_latest_version_matching_existing_precision }
    let(:repo_url) { "https://github.com/gocardless/business.git" }
    let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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

    context "with no tags, nor version branches" do
      let(:upload_pack_fixture) { "no_tags" }
      it { is_expected.to be_nil }
    end

    context "with no version tags nor version branches" do
      let(:upload_pack_fixture) { "no_versions" }
      it { is_expected.to be_nil }
    end

    context "with version tags, and some version branches not matching pinned schema" do
      let(:upload_pack_fixture) { "actions-checkout" }
      let(:version) { "1.1.1" }

      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "v#{version}"
        }
      end

      let(:latest_patch) do
        {
          commit_sha: "5a4ac9002d0be2fb38bd78e4b4dbde5606d7042f",
          tag: "v2.3.4",
          tag_sha: anything,
          version: anything
        }
      end

      it { is_expected.to match(latest_patch) }
    end

    context "with a version branch higher than the latest version tag, and pinned to the commit sha of a version tag" do
      let(:upload_pack_fixture) { "actions-checkout-2022-12-01" }
      let(:version) { "1.1.0" }

      let(:source) do
        {
          type: "git",
          url: "https://github.com/gocardless/business",
          branch: "master",
          ref: "0b496e91ec7ae4428c3ed2eeb4c3a40df431f2cc"
        }
      end

      let(:latest_patch) do
        {
          commit_sha: "93ea575cb5d8a053eaa0ac8fa3b40d7e05a33cc8",
          tag: "v3.1.0",
          tag_sha: anything,
          version: anything
        }
      end

      it { is_expected.to match(latest_patch) }
    end

    context "with tags for minor versions and branches for major versions" do
      let(:upload_pack_fixture) { "run-vcpkg" }

      context "when pinned to a major" do
        let(:version) { "7" }

        let(:latest_major_branch) do
          {
            commit_sha: "831e6cd560cc8688a4967c5766e4215afbd196d9",
            tag: "v10",
            tag_sha: anything,
            version: anything
          }
        end

        it { is_expected.to match(latest_major_branch) }
      end

      context "when pinned to a minor" do
        let(:version) { "7.0" }

        let(:latest_minor_tag) do
          {
            commit_sha: "831e6cd560cc8688a4967c5766e4215afbd196d9",
            tag: "v10.6",
            tag_sha: anything,
            version: anything
          }
        end

        it { is_expected.to match(latest_minor_tag) }
      end
    end
  end

  describe "#local_tag_for_pinned_sha" do
    subject { checker.local_tag_for_pinned_sha }

    context "with a git commit pin" do
      let(:source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          branch: "main",
          ref: source_commit
        }
      end

      let(:repo_url) { "https://github.com/actions/checkout.git" }
      let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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
      let(:upload_pack_fixture) { "actions-checkout" }

      context "that is a tag" do
        let(:source_commit) { "a81bbbf8298c0fa03ea29cdc473d45769f953675" }

        it { is_expected.to eq("v2.3.3") }
      end

      context "that is not a tag" do
        let(:source_commit) { "25a956c84d5dd820d28caab9f86b8d183aeeff3d" }

        it { is_expected.to be_nil }
      end

      context "that is an invalid tag" do
        let(:source_commit) { "18217bbd6de24e775799c3d99058f167ad168624" }

        it { is_expected.to be_nil }
      end

      context "that is not found" do
        let(:source_commit) { "f0987d27b23cb3fd0e97eb7908c1a27df5bf8329" }

        it { is_expected.to be_nil }
      end

      context "that is multiple tags" do
        let(:source_commit) { "5a4ac9002d0be2fb38bd78e4b4dbde5606d7042f" }

        it { is_expected.to eq("v2.3.4") }
      end
    end
  end

  describe "#most_specific_tag_equivalent_to_pinned_ref" do
    subject { checker.most_specific_tag_equivalent_to_pinned_ref }

    let(:source) do
      {
        type: "git",
        url: "https://github.com/actions/checkout",
        branch: "main",
        ref: source_ref
      }
    end

    let(:repo_url) { "https://github.com/actions/checkout.git" }
    let(:service_pack_url) { repo_url + "/info/refs?service=git-upload-pack" }
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
    let(:upload_pack_fixture) { "actions-checkout-moving-v2" }

    context "for a moving major tag" do
      let(:source_ref) { "v2" }

      it { is_expected.to eq("v2.3.4") }
    end

    context "for a fixed patch tag" do
      let(:source_ref) { "v2.3.4" }

      it { is_expected.to eq("v2.3.4") }
    end
  end

  describe "#git_repo_reachable?" do
    subject { checker.git_repo_reachable? }

    let(:source) do
      {
        type: "git",
        url: "https://github.com/gocardless/business",
        branch: "master",
        ref: "master"
      }
    end
    let(:git_header) do
      { "content-type" => "application/x-git-upload-pack-advertisement" }
    end
    let(:auth_header) { "Basic eC1hY2Nlc3MtdG9rZW46dG9rZW4=" }

    let(:git_url) do
      "https://github.com/gocardless/business.git" \
        "/info/refs?service=git-upload-pack"
    end

    context "that can be reached just fine" do
      before do
        stub_request(:get, git_url).
          with(headers: { "Authorization" => auth_header }).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "business"),
            headers: git_header
          )
      end

      it { is_expected.to eq(true) }
    end

    context "that results in a 403" do
      let(:url) { "https://github.com/gocardless/business.git" }

      before do
        stub_request(:get, git_url).
          with(headers: { "Authorization" => auth_header }).
          to_return(status: 403)

        exit_status = double(success?: false)
        allow(Open3).to receive(:capture3).and_call_original
        allow(Open3).to receive(:capture3).with(anything, "git ls-remote #{url}").and_return(["", "", exit_status])
      end

      it { is_expected.to eq(false) }
    end
  end
end
