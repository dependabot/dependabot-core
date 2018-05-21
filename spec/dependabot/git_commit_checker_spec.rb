# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/git_commit_checker"

RSpec.describe Dependabot::GitCommitChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end

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
    [
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      },
      {
        "some" => "irrelevant credential"
      }
    ]
  end

  describe "#git_dependency?" do
    subject { checker.git_dependency? }

    context "with a non-git dependency" do
      let(:source) { nil }
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

      let(:rubygems_url) { "https://rubygems.org/api/v1/gems/business.json" }
      let(:rubygems_response_code) { 200 }
      let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
      before do
        stub_request(:get, rubygems_url).
          to_return(status: rubygems_response_code, body: rubygems_response)
      end

      context "with no rubygems listing" do
        let(:rubygems_response_code) { 404 }
        let(:rubygems_response) { "This rubygem could not be found." }
        it { is_expected.to eq(false) }
      end

      context "with source code hosted on GitHub" do
        let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
        let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
        let(:service_pack_url) do
          "https://github.com/gocardless/business.git/info/refs"\
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
          before { stub_request(:get, service_pack_url).to_return(status: 404) }
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
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_bitbucket.json")
        end
        let(:service_pack_url) do
          "https://bitbucket.org/gocardless/business.git/info/refs"\
          "?service=git-upload-pack"
        end
        let(:bitbucket_url) do
          "https://api.bitbucket.org/2.0/repositories/"\
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
          end
          let(:ref) { "my_ref" }

          it "raises a helpful error" do
            expect { checker.head_commit_for_current_branch }.
              to raise_error(Dependabot::GitDependenciesNotReachable)
          end
        end

        context "when the source returns a timeout" do
          before do
            git_url = "https://github.com/gocardless/business.git"
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              to_raise(Excon::Error::Timeout)
          end
          let(:ref) { "my_ref" }

          it "raises a helpful error" do
            expect { checker.head_commit_for_current_branch }.
              to raise_error(Dependabot::GitDependenciesNotReachable)
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
      it { is_expected.to eq(dependency.version) }
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
        before do
          stub_request(:get, git_url).
            with(headers: { "Authorization" => auth_header }).
            to_return(status: 403)
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
                  url: "https://x-access-token:token@bitbucket.org/gocardless/"\
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
      before { stub_request(:get, service_pack_url).to_return(status: 404) }

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
      end
    end
  end
end
