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
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
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

      context "with source code not hosted on GitHub" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_bitbucket.json")
        end
        it { is_expected.to eq(false) }
      end

      context "with source code hosted on GitHub" do
        let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
        let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
        let(:tags_url) { repo_url + "/tags?per_page=100" }
        before do
          stub_request(:get, tags_url).to_return(
            status: 200,
            body: tags_response,
            headers: { "Content-Type" => "application/json" }
          )
        end

        context "but no tags on GitHub" do
          let(:tags_response) { [].to_json }
          it { is_expected.to eq(false) }
        end

        context "but GitHub returns a 404" do
          before { stub_request(:get, tags_url).to_return(status: 404) }
          let(:tags_response) { "unused" }
          it { is_expected.to eq(false) }
        end

        context "with tags on GitHub" do
          let(:tags_response) { fixture("github", "business_tags.json") }
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

        it { is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e") }

        context "with no branch specified" do
          let(:source) do
            {
              type: "git",
              url: "https://github.com/gocardless/business",
              branch: nil,
              ref: nil
            }
          end

          it { is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e") }
        end

        context "specified with an SSH URL" do
          before { source.merge!(url: "git@github.com:gocardless/business") }

          it { is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e") }
        end

        context "specified with a git URL" do
          before do
            source.merge!(url: "git://github.com/gocardless/business.git")
          end

          it { is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e") }
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
                "host" => "bitbucket.org",
                "username" => "x-access-token",
                "password" => "token"
              }]
            end

            it { is_expected.to eq("d31e445215b5af70c1604715d97dd953e868380e") }
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
    let(:repo_url) { "https://api.github.com/repos/gocardless/business" }
    let(:tags_url) { repo_url + "/tags?per_page=100" }
    before do
      stub_request(:get, tags_url).to_return(
        status: 200,
        body: tags_response,
        headers: { "Content-Type" => "application/json" }
      )
    end

    context "with no tags on GitHub" do
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "with a non-GitHub URL" do
      before { source.merge(url: "https://example.com") }
      let(:tags_response) { [].to_json }
      it { is_expected.to eq(nil) }
    end

    context "but GitHub returns a 404" do
      before { stub_request(:get, tags_url).to_return(status: 404) }
      let(:tags_response) { "unused" }
      it { is_expected.to eq(nil) }
    end

    context "with tags on GitHub" do
      context "but no version tags" do
        let(:tags_response) do
          fixture("github", "business_tags_no_versions.json")
        end
        it { is_expected.to eq(nil) }
      end

      context "with version tags" do
        let(:tags_response) { fixture("github", "business_tags.json") }
        before do
          stub_request(:get, repo_url + "/git/refs/tags/v1.6.0").
            to_return(
              status: 200,
              body: fixture("github", "ref.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end
        its([:tag]) { is_expected.to eq("v1.6.0") }
        its([:commit_sha]) do
          is_expected.to eq("66d39bf3042fac0b770bca2bfb200cfdffcd0175")
        end
        its([:tag_sha]) do
          is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd")
        end
      end

      context "with prefixed tags" do
        let(:tags_response) { fixture("github", "prefixed_tags.json") }
        before do
          stub_request(:get, repo_url + "/git/refs/tags/business-21.4.0").
            to_return(
              status: 200,
              body: fixture("github", "ref.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end
        its([:tag]) { is_expected.to eq("business-21.4.0") }
        its([:commit_sha]) do
          is_expected.to eq("55d39bf3042fac0b770bca2bfb200cfdffcd0175")
        end
        its([:tag_sha]) do
          is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd")
        end
      end
    end
  end
end
