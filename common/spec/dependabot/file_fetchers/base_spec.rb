# typed: false
# frozen_string_literal: true

require "aws-sdk-codecommit"
require "octokit"
require "fileutils"
require "spec_helper"
require "dependabot/credential"
require "dependabot/source"
require "dependabot/file_fetchers/base"
require "dependabot/clients/codecommit"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::FileFetchers::Base do
  let(:source) do
    Dependabot::Source.new(
      provider: provider,
      repo: repo,
      directory: directory,
      branch: branch,
      commit: source_commit
    )
  end
  let(:repo_contents_path) { nil }
  let(:child_class) do
    Class.new(described_class) do
      def self.required_files_in?(filenames)
        filenames.include?("requirements.txt")
      end

      def self.required_files_message
        "Repo must contain a requirements.txt."
      end

      private

      def fetch_files
        [fetch_file_from_host("requirements.txt")]
      end
    end
  end
  let(:file_fetcher_instance) do
    child_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: repo_contents_path
    )
  end
  let(:provider) { "github" }
  let(:repo) { "gocardless/bump" }
  let(:directory) { "/" }
  let(:branch) { nil }
  let(:source_commit) { nil }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "region" => "us-east-1",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:stubbed_cc_client) { Aws::CodeCommit::Client.new(stub_responses: true) }

  before do
    allow_any_instance_of(
      Dependabot::Clients::CodeCommit
    ).to receive(:cc_client).and_return(stubbed_cc_client)
  end

  describe "#commit" do
    subject(:commit) { file_fetcher_instance.commit }

    context "with a GitHub source" do
      let(:url) { "https://api.github.com/repos/#{repo}" }

      before do
        stub_request(:get, url)
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200,
                     body: fixture("github", "bump_repo.json"),
                     headers: { "content-type" => "application/json" })
        stub_request(:get, url + "/git/refs/heads/master")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200,
                     body: fixture("github", "ref.json"),
                     headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd") }

      context "when the repo is empty" do
        before do
          stub_request(:get, url + "/git/refs/heads/master")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 409,
                       body: fixture("github", "git_repo_empty.json"),
                       headers: { "content-type" => "application/json" })
        end

        it { is_expected.to be_nil }
      end

      context "with a target branch" do
        let(:branch) { "my_branch" }

        before do
          stub_request(:get, url + "/git/refs/heads/my_branch")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 200,
                       body: fixture("github", "ref_my_branch.json"),
                       headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("bb218f56b14c9653891f9e74264a383fa43fefbd") }

        context "when branch can't be found" do
          before do
            stub_request(:get, url + "/git/refs/heads/my_branch")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404,
                         headers: { "content-type" => "application/json" })
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::BranchNotFound) do |error|
                expect(error.branch_name).to eq("my_branch")
              end
          end
        end

        context "when returning an array (because it is a substring)" do
          before do
            stub_request(:get, url + "/git/refs/heads/my_branch")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 200,
                         body: fixture("github", "ref_my_branch_many.json"),
                         headers: { "content-type" => "application/json" })
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::BranchNotFound) do |error|
                expect(error.branch_name).to eq("my_branch")
              end
          end
        end
      end
    end

    context "with a GitLab source" do
      let(:provider) { "gitlab" }
      let(:base_url) { "https://gitlab.com/api/v4" }
      let(:project_url) { base_url + "/projects/gocardless%2Fbump" }
      let(:branch_url) { project_url + "/repository/branches/master" }

      before do
        stub_request(:get, project_url)
          .to_return(status: 200,
                     body: fixture("gitlab", "bump_repo.json"),
                     headers: { "content-type" => "application/json" })
        stub_request(:get, branch_url)
          .to_return(status: 200,
                     body: fixture("gitlab", "master_branch.json"),
                     headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("f7dd067490fe57505f7226c3b54d3127d2f7fd46") }

      context "with a target branch" do
        let(:branch) { "my_branch" }
        let(:branch_url) { project_url + "/repository/branches/my_branch" }

        before do
          stub_request(:get, branch_url)
            .to_return(status: 200,
                       body: fixture("gitlab", "branch.json"),
                       headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("b7dd067490fe57505f7226c3b54d3127d2f7fd41") }
      end
    end

    context "with a Bitbucket source" do
      let(:provider) { "bitbucket" }
      let(:base_url) { "https://api.bitbucket.org/2.0" }
      let(:repo_url) { base_url + "/repositories/gocardless/bump" }
      let(:branch_url) { repo_url + "/refs/branches/default" }

      before do
        stub_request(:get, repo_url)
          .to_return(status: 200,
                     body: fixture("bitbucket", "bump_repo.json"),
                     headers: { "content-type" => "application/json" })
        stub_request(:get, branch_url)
          .to_return(status: 200,
                     body: fixture("bitbucket", "default_branch.json"),
                     headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("0fd7bb2494e8cc11c71c05f8f12deafa6b41fb37") }

      context "with a target branch" do
        let(:branch) { "my_branch" }
        let(:branch_url) { repo_url + "/refs/branches/my_branch" }

        before do
          stub_request(:get, branch_url)
            .to_return(status: 200,
                       body: fixture("bitbucket", "other_branch.json"),
                       headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("4c2ea65f2eb932c438557cb6ec29b984794c6108") }
      end
    end

    context "with a CodeCommit source" do
      let(:provider) { "codecommit" }
      let(:repo) { "gocardless" }

      before do
        stubbed_cc_client
          .stub_responses(
            :get_branch,
            branch:
              {
                branch_name: "master",
                commit_id: "9c8376e9b2e943c2c72fac4b239876f377f0305a"
              }
          )
      end

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }

      context "with a target branch" do
        let(:branch) { "my_branch" }

        before do
          stubbed_cc_client
            .stub_responses(
              :get_branch,
              branch:
                {
                  branch_name: "my_branch",
                  commit_id: "8c8376e9b2e943c2c72fac4b239876f377f0305b"
                }
            )
        end

        it { is_expected.to eq("8c8376e9b2e943c2c72fac4b239876f377f0305b") }
      end
    end

    context "with a Azure DevOps source" do
      let(:provider) { "azure" }
      let(:repo) { "org/gocardless/_git/bump" }
      let(:base_url) { "https://dev.azure.com/org/gocardless" }
      let(:repo_url) { base_url + "/_apis/git/repositories/bump" }
      let(:branch_url) { repo_url + "/stats/branches?name=master" }

      before do
        stub_request(:get, repo_url)
          .to_return(status: 200,
                     body: fixture("azure", "bump_repo.json"),
                     headers: { "content-type" => "application/json" })
        stub_request(:get, branch_url)
          .to_return(status: 200,
                     body: fixture("azure", "master_branch.json"),
                     headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }

      context "with a target branch" do
        let(:branch) { "my_branch" }
        let(:branch_url) { repo_url + "/stats/branches?name=my_branch" }

        before do
          stub_request(:get, branch_url)
            .to_return(status: 200,
                       body: fixture("azure", "other_branch.json"),
                       headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("8c8376e9b2e943c2c72fac4b239876f377f0305b") }
      end
    end

    # NOTE: only used locally when testing against specific commits
    context "with a source commit" do
      let(:source_commit) { "0e8b8c801024c811d434660f8cf09809f9eb9540" }

      it { is_expected.to eq("0e8b8c801024c811d434660f8cf09809f9eb9540") }
    end
  end

  describe "#files" do
    subject(:files) { file_fetcher_instance.files }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    end

    context "with a GitHub source" do
      let(:url) { "https://api.github.com/repos/#{repo}/contents/" }

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200,
                     body: fixture("github", "gemfile_content.json"),
                     headers: { "content-type" => "application/json" })
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject(:files_find) { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("octokit") }

        context "when there are non-ASCII characters" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "gemfile_content_non_ascii.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          its(:content) { is_expected.to eq("öäöä") }
        end

        context "when it includes a BOM" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "bom.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "is stripped" do
            expect(files_find.content.bytes.first(3)).not_to eq(["EF".hex, "BB".hex, "BF".hex])
          end
        end

        context "when the file is a directory" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
                expect(error.file_path).to eq("/requirements.txt")
              end
          end
        end
      end

      context "with a directory specified" do
        context "when ending in a slash" do
          let(:directory) { "app/" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "when beginning with a slash" do
          let(:directory) { "/app" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "when including a slash" do
          let(:directory) { "a/pp" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/a/pp/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/requirements.txt")
            end
        end
      end

      context "when a dependency file returns a symlink" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "symlinked_file_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "symlinked/requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("octokit") }
          its(:type) { is_expected.to include("symlink") }

          its(:symlink_target) do
            is_expected.to include("symlinked/requirements.txt")
          end
        end
      end

      context "when the file is in a directory" do
        let(:child_class) do
          Class.new(described_class) do
            def fetch_files
              [fetch_file_from_host("some/dir/req.txt")]
            end
          end
        end

        before do
          stub_request(:get, url + "some/dir/req.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        describe "the file" do
          subject { files.find { |file| file.name == "some/dir/req.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("octokit") }
        end

        context "when the file is in a submodule (shallow)" do
          before do
            stub_request(:get, url + "some/dir/req.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404)
            submodule_details =
              fixture("github", "submodule.json")
              .gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
            stub_request(:get, url + "some/dir?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: submodule_details,
                headers: { "content-type" => "application/json" }
              )

            sub_url = "https://api.github.com/repos/dependabot/" \
                      "manifesto/contents/"
            stub_request(:get, sub_url + "?ref=sha2")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "req.txt?ref=sha2")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
                expect(error.file_path).to eq("/some/dir/req.txt")
              end
          end

          context "with fetching submodule files requested" do
            let(:child_class) do
              Class.new(described_class) do
                def fetch_files
                  [
                    fetch_file_from_host(
                      "some/dir/req.txt",
                      fetch_submodules: true
                    )
                  ]
                end
              end
            end

            describe "the file" do
              subject { files.find { |file| file.name == "some/dir/req.txt" } }

              it { is_expected.to be_a(Dependabot::DependencyFile) }
              its(:content) { is_expected.to include("octokit") }
            end
          end
        end

        context "when the file is in a submodule (deep)" do
          before do
            stub_request(:get, url + "some/dir/req.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404)
            stub_request(:get, url + "some/dir?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404)
            submodule_details =
              fixture("github", "submodule.json")
              .gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
            stub_request(:get, url + "some?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: submodule_details,
                headers: { "content-type" => "application/json" }
              )

            sub_url = "https://api.github.com/repos/dependabot/" \
                      "manifesto/contents/"
            stub_request(:get, sub_url + "?ref=sha2")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: "[]",
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "dir?ref=sha2")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "dir/req.txt?ref=sha2")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
                expect(error.file_path).to eq("/some/dir/req.txt")
              end
          end

          context "with fetching submodule files requested" do
            let(:child_class) do
              Class.new(described_class) do
                def fetch_files
                  [
                    fetch_file_from_host(
                      "some/dir/req.txt",
                      fetch_submodules: true
                    )
                  ]
                end
              end
            end

            describe "the file" do
              subject { files.find { |file| file.name == "some/dir/req.txt" } }

              it { is_expected.to be_a(Dependabot::DependencyFile) }
              its(:content) { is_expected.to include("octokit") }
            end
          end
        end

        context "when the file is in a symlinked directory" do
          before do
            stub_request(:get, url + "some/dir/req.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404)
            stub_request(:get, url + "some/dir?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(status: 404)
            symlink_details =
              fixture("github", "symlinked_repo.json")
              .gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
            stub_request(:get, url + "some?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: symlink_details,
                headers: { "content-type" => "application/json" }
              )

            stub_request(:get, url + "symlinked/repo?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: "[]",
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "symlinked/repo/dir?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "symlinked/repo/dir/req.txt?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
                expect(error.file_path).to eq("/some/dir/req.txt")
              end
          end

          context "with fetching submodule files requested" do
            let(:child_class) do
              Class.new(described_class) do
                def fetch_files
                  [
                    fetch_file_from_host(
                      "some/dir/req.txt",
                      fetch_submodules: true
                    )
                  ]
                end
              end
            end

            describe "the file" do
              subject { files.find { |file| file.name == "some/dir/req.txt" } }

              it { is_expected.to be_a(Dependabot::DependencyFile) }
              its(:content) { is_expected.to include("octokit") }
            end
          end
        end
      end

      context "when a dependency file is too big to download" do
        let(:blob_url) do
          "https://api.github.com/repos/#{repo}/git/blobs/" \
            "88b4e0a1c8093fae2b4fa52534035f9f85ed0956"
        end

        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 403,
              body: fixture("github", "file_too_large.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "contents_python.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, blob_url)
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "git_data_requirements_blob.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "falls back to the git data API" do
          expect(files.first.content).to include("-r common.txt")
          expect(WebMock).to have_requested(:get, blob_url)
        end

        context "with a directory specified" do
          let(:directory) { "app/" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

          before do
            stub_request(:get, url.gsub(%r{/$}, "") + "?ref=sha")
              .with(headers: { "Authorization" => "token token" })
              .to_return(
                status: 200,
                body: fixture("github", "contents_python.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end
      end
    end

    context "with a GitLab source" do
      let(:provider) { "gitlab" }
      let(:base_url) { "https://gitlab.com/api/v4" }
      let(:project_url) { base_url + "/projects/gocardless%2Fbump" }

      let(:url) { project_url + "/repository/files/" }

      before do
        stub_request(:get, url + "requirements.txt?ref=sha")
          .to_return(status: 200,
                     body: fixture("gitlab", "gemfile_content.json"),
                     headers: { "content-type" => "application/json" })
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject(:files_find) { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("octokit") }

        context "when there are non-ASCII characters" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .to_return(
                status: 200,
                body: fixture("gitlab", "gemfile_content_non_ascii.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          its(:content) { is_expected.to eq("öäöä") }
        end

        context "when it includes a BOM" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha")
              .to_return(
                status: 200,
                body: fixture("gitlab", "bom.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "is stripped" do
            expect(files_find.content.bytes.first(3)).not_to eq(["EF".hex, "BB".hex, "BF".hex])
          end
        end
      end

      context "with a directory specified" do
        let(:file_fetcher_instance) do
          child_class.new(source: source, credentials: credentials)
        end

        context "when ending with a slash" do
          let(:directory) { "app/" }
          let(:url) { project_url + "/repository/files/app%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "when beginning with a slash" do
          let(:directory) { "/app" }
          let(:url) { project_url + "/repository/files/app%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "when including a slash" do
          let(:directory) { "a/pp" }
          let(:url) { project_url + "/repository/files/a%2Fpp%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock)
              .to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha")
            .to_return(
              status: 404,
              body: fixture("gitlab", "not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/requirements.txt")
            end
        end
      end
    end

    context "with a Bitbucket source" do
      let(:provider) { "bitbucket" }
      let(:base_url) { "https://api.bitbucket.org/2.0" }
      let(:repo_url) { base_url + "/repositories/gocardless/bump" }
      let(:url) { repo_url + "/src/sha/requirements.txt" }

      before do
        stub_request(:get, url)
          .to_return(status: 200,
                     body: fixture("bitbucket", "gemspec_content"),
                     headers: { "content-type" => "text/plain" })
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("required_rubygems_version") }
      end

      context "with a directory specified" do
        let(:file_fetcher_instance) do
          child_class.new(source: source, credentials: credentials)
        end

        context "when ending with a slash" do
          let(:directory) { "app/" }
          let(:url) { repo_url + "/src/sha/app/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "when beginning with a slash" do
          let(:directory) { "/app" }
          let(:url) { repo_url + "/src/sha/app/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "when including a slash" do
          let(:directory) { "a/pp" }
          let(:url) { repo_url + "/src/sha/a/pp/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url)
            .to_return(
              status: 404,
              body: fixture("bitbucket", "file_not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/requirements.txt")
            end
        end
      end

      context "when fetching the file only if present" do
        let(:child_class) do
          Class.new(described_class) do
            def self.required_files_in?(filenames)
              filenames.include?("requirements.txt")
            end

            def self.required_files_message
              "Repo must contain a requirements.txt."
            end

            private

            def fetch_files
              [fetch_file_if_present("requirements.txt")].compact
            end
          end
        end

        let(:repo_contents_url) { repo_url + "/src/sha/?pagelen=100" }

        before do
          stub_request(:get, repo_contents_url)
            .to_return(status: 200,
                       body: fixture("bitbucket", "business_files.json"),
                       headers: { "content-type" => "application/json" })
        end

        its(:length) { is_expected.to eq(1) }

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("required_rubygems_version") }
        end

        context "when the file can't be found" do
          before do
            stub_request(:get, repo_contents_url)
              .to_return(status: 200,
                         body: fixture("bitbucket", "no_files.json"),
                         headers: { "content-type" => "application/json" })
          end

          it "raises an exception" do
            expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
          end
        end

        context "with a directory" do
          let(:directory) { "/app" }
          let(:repo_contents_url) { repo_url + "/src/sha/app?pagelen=100" }
          let(:url) { repo_url + "/src/sha/app/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end
      end
    end

    context "with a Azure DevOps source" do
      let(:provider) { "azure" }
      let(:repo) { "org/gocardless/_git/bump" }
      let(:base_url) { "https://dev.azure.com/org/gocardless" }
      let(:repo_url) { base_url + "/_apis/git/repositories/bump" }
      let(:url) do
        repo_url + "/items?path=requirements.txt" \
                   "&versionDescriptor.version=sha&versionDescriptor.versionType=commit"
      end

      before do
        stub_request(:get, url)
          .to_return(status: 200,
                     body: fixture("azure", "gemspec_content"),
                     headers: { "content-type" => "text/plain" })
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("required_rubygems_version") }
      end

      context "with a directory specified" do
        let(:file_fetcher_instance) do
          child_class.new(source: source, credentials: credentials)
        end

        context "when ending in a slash" do
          let(:directory) { "app/" }
          let(:url) do
            repo_url + "/items?path=app/requirements.txt" \
                       "&versionDescriptor.version=sha" \
                       "&versionDescriptor.versionType=commit"
          end

          it "hits the right Azure DevOps URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "when beginning with a slash" do
          let(:directory) { "/app" }
          let(:url) do
            repo_url + "/items?path=app/requirements.txt" \
                       "&versionDescriptor.version=sha" \
                       "&versionDescriptor.versionType=commit"
          end

          it "hits the right Azure DevOps URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "when including a slash" do
          let(:directory) { "a/pp" }
          let(:url) do
            repo_url + "/items?path=a/pp/requirements.txt" \
                       "&versionDescriptor.version=sha" \
                       "&versionDescriptor.versionType=commit"
          end

          it "hits the right Azure DevOps URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url)
            .to_return(
              status: 404,
              body: fixture("bitbucket", "file_not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/requirements.txt")
            end
        end
      end

      context "when fetching the file only if present" do
        let(:child_class) do
          Class.new(described_class) do
            def self.required_files_in?(filenames)
              filenames.include?("requirements.txt")
            end

            def self.required_files_message
              "Repo must contain a requirements.txt."
            end

            private

            def fetch_files
              [fetch_file_if_present("requirements.txt")].compact
            end
          end
        end

        let(:repo_contents_tree_url) do
          repo_url + "/items?path=/&versionDescriptor.version=sha" \
                     "&versionDescriptor.versionType=commit"
        end
        let(:repo_contents_url) do
          repo_url + "/trees/9fea8a9fd1877daecde8f80137f9dfee6ec0b01a" \
                     "?recursive=false"
        end
        let(:repo_file_url) do
          repo_url + "/items?path=requirements.txt" \
                     "&versionDescriptor.version=sha" \
                     "&versionDescriptor.versionType=commit"
        end

        before do
          stub_request(:get, repo_contents_tree_url)
            .to_return(status: 200,
                       body: fixture("azure", "business_folder.json"),
                       headers: { "content-type" => "text/plain" })
          stub_request(:get, repo_contents_url)
            .to_return(status: 200,
                       body: fixture("azure", "business_files.json"),
                       headers: { "content-type" => "application/json" })
          stub_request(:get, repo_file_url)
            .to_return(status: 200,
                       body: fixture("azure", "gemspec_content"),
                       headers: { "content-type" => "text/plain" })
        end

        its(:length) { is_expected.to eq(1) }

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("required_rubygems_version") }
        end

        context "when the file can't be found" do
          before do
            stub_request(:get, repo_contents_url)
              .to_return(status: 200,
                         body: fixture("azure", "no_files.json"),
                         headers: { "content-type" => "application/json" })
          end

          it "raises an exception" do
            expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
          end
        end

        context "with a directory" do
          let(:directory) { "/app" }
          let(:url) do
            repo_url + "/items?path=app&versionDescriptor.version=sha" \
                       "&versionDescriptor.versionType=commit"
          end

          let(:repo_contents_tree_url) do
            repo_url + "/items?path=app&versionDescriptor.version=sha" \
                       "&versionDescriptor.versionType=commit"
          end
          let(:repo_contents_url) do
            repo_url + "/trees/9fea8a9fd1877daecde8f80137f9dfee6ec0b01a" \
                       "?recursive=false"
          end

          before do
            stub_request(:get, repo_contents_tree_url)
              .to_return(status: 200,
                         body: fixture("azure", "business_folder.json"),
                         headers: { "content-type" => "text/plain" })
            stub_request(:get, repo_contents_url)
              .to_return(status: 200,
                         body: fixture("azure", "no_files.json"),
                         headers: { "content-type" => "application/json" })
          end

          it "hits the right Azure DevOps URL" do
            expect { files }.to raise_error(Dependabot::DependencyFileNotFound)
            expect(WebMock).to have_requested(:get, url)
          end
        end
      end
    end

    context "with a CodeCommit source" do
      let(:provider) { "codecommit" }
      let(:repo) { "gocardless" }

      before do
        stubbed_cc_client
          .stub_responses(
            :get_file,
            commit_id: "9c8376e9b2e943c2c72fac4b239876f377f0305a",
            blob_id: "123",
            file_path: "",
            file_mode: "NORMAL",
            file_size: 0,
            file_content: fixture("codecommit", "gemspec_content")
          )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject(:files_find) { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("required_rubygems_version") }
      end

      context "with directory path specified" do
        let(:file_fetcher_instance) do
          child_class.new(source: source, credentials: credentials)
        end

        context "when ending with a slash" do
          before do
            stubbed_cc_client
              .stub_responses(
                :get_file,
                commit_id: "",
                blob_id: "",
                file_path: "app/requirements.txt",
                file_mode: "NORMAL",
                file_size: 0,
                file_content: "foo"
              )
          end

          let(:directory) { "app/" }

          it "gets the file" do
            expect { files }.not_to raise_error
          end
        end

        context "when beginning with a slash" do
          before do
            stubbed_cc_client
              .stub_responses(
                :get_file,
                commit_id: "",
                blob_id: "",
                file_path: "/app/requirements.txt",
                file_mode: "NORMAL",
                file_size: 0,
                file_content: "foo"
              )
          end

          let(:directory) { "/app" }

          it "gets the file" do
            expect { files }.not_to raise_error
          end
        end

        context "when including a slash" do
          before do
            stubbed_cc_client
              .stub_responses(
                :get_file,
                commit_id: "",
                blob_id: "",
                file_path: "a/pp/requirements.txt",
                file_mode: "NORMAL",
                file_size: 0,
                file_content: "foo"
              )
          end

          let(:directory) { "a/pp" }

          it "gets the file" do
            expect { files }.not_to raise_error
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stubbed_cc_client
            .stub_responses(
              :get_file,
              "FileDoesNotExistException"
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.file_path).to eq("/requirements.txt")
          end
        end
      end
    end

    context "with an interesting filename" do
      let(:file_fetcher_instance) do
        child_class.new(source: source, credentials: credentials)
      end

      before do
        stub_request(:get, file_url)
          .with(headers: { "Authorization" => "token token" })
          .to_return(status: 200,
                     body: fixture("github", "gemfile_content.json"),
                     headers: { "content-type" => "application/json" })
      end

      context "with a '.'" do
        let(:directory) { "/" }
        let(:url) { "https://api.github.com/repos/#{repo}/contents/" }
        let(:file_url) do
          "https://api.github.com/repos/#{repo}/contents/some/file?ref=sha"
        end
        let(:child_class) do
          Class.new(described_class) do
            def fetch_files
              [fetch_file_from_host("./some/file")]
            end
          end
        end

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, file_url)
        end
      end

      context "with a '..'" do
        let(:directory) { "app" }
        let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }
        let(:file_url) do
          "https://api.github.com/repos/#{repo}/contents/some/file?ref=sha"
        end
        let(:child_class) do
          Class.new(described_class) do
            def fetch_files
              [fetch_file_from_host("../some/file")]
            end
          end
        end

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, file_url)
        end
      end
    end
  end

  context "with repo_contents_path" do
    let(:repo_contents_path) { Dir.mktmpdir }

    after { FileUtils.rm_rf(repo_contents_path) }

    describe "#files" do
      subject(:files) { file_fetcher_instance.files }

      let(:contents) { "foo=1.0.0" }
      let(:fill_repo) { nil }

      # `git clone` against a file:// URL that is filled by the test
      let(:repo_path) { Dir.mktmpdir }

      after { FileUtils.rm_rf(repo_path) }

      before do
        Dir.chdir(repo_path) do
          `git init --initial-branch main .`
          fill_repo
          `git add .`
          `git commit --allow-empty -m'fake clone source'`
        end

        allow(source)
          .to receive(:url).and_return("file://#{repo_path}")
        allow(file_fetcher_instance).to receive(:commit).and_return("sha")
      end

      context "with a git source" do
        let(:fill_repo) do
          File.write("requirements.txt", contents)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to eq(contents) }
          its(:directory) { is_expected.to eq("/") }
        end

        context "with an optional file" do
          let(:child_class) do
            Class.new(described_class) do
              def self.required_files_in?(filenames)
                filenames.include?("requirements.txt")
              end

              def self.required_files_message
                "Repo must contain a requirements.txt."
              end

              private

              def fetch_files
                files = [fetch_file_from_host("requirements.txt")]
                files << optional if optional
                files
              end

              def optional
                return @optional if defined?(@optional)

                @optional = fetch_file_if_present("not-present.txt")
              end
            end
          end

          its(:length) { is_expected.to eq(1) }

          describe "the file" do
            subject { files.find { |file| file.name == "requirements.txt" } }

            it { is_expected.to be_a(Dependabot::DependencyFile) }
          end
        end
      end

      context "with an invalid source" do
        before do
          allow(source)
            .to receive(:url).and_return("file://does/not/exist")
        end

        it "raises RepoNotFound" do
          expect { files }
            .to raise_error(Dependabot::RepoNotFound)
        end
      end

      context "when the file is not found" do
        it "raises DependencyFileNotFound" do
          expect { files }
            .to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.file_path).to eq("/requirements.txt")
          end
        end
      end

      context "when the directory is symlinked" do
        let(:fill_repo) do
          Dir.mkdir("symlinked")
          file_path = File.join("symlinked", "requirements.txt")
          File.write(file_path, contents)
          File.symlink(file_path, "requirements.txt")
        end

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:type) { is_expected.to include("symlink") }

          its(:symlink_target) do
            is_expected.to include("symlinked/requirements.txt")
          end
        end
      end

      context "when the file is in a directory" do
        let(:child_class) do
          Class.new(described_class) do
            def self.required_files_in?(filenames)
              filenames.include?("nested/requirements.txt")
            end

            def self.required_files_message
              "Repo must contain a nested/requirements.txt."
            end

            private

            def fetch_files
              [fetch_file_from_host("nested/requirements.txt")]
            end
          end
        end

        context "when the file is not found" do
          it "raises DependencyFileNotFound" do
            expect { files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/nested/requirements.txt")
            end
          end
        end

        context "with a git source" do
          let(:fill_repo) do
            Dir.mkdir("nested")
            path = File.join("nested", "requirements.txt")
            File.write(path, contents)
          end

          its(:length) { is_expected.to eq(1) }

          describe "the file" do
            subject do
              files.find { |file| file.name == "nested/requirements.txt" }
            end

            it { is_expected.to be_a(Dependabot::DependencyFile) }
            its(:content) { is_expected.to eq(contents) }
            its(:directory) { is_expected.to eq("/") }
          end
        end
      end

      context "with a directory specified" do
        let(:directory) { "/nested" }

        context "when the file is not found" do
          it "raises DependencyFileNotFound" do
            expect { files }
              .to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/nested/requirements.txt")
            end
          end
        end

        context "with a git source" do
          let(:fill_repo) do
            Dir.mkdir("nested")
            path = File.join("nested", "requirements.txt")
            File.write(path, contents)
          end

          its(:length) { is_expected.to eq(1) }

          describe "the file" do
            subject do
              files.find { |file| file.name == "requirements.txt" }
            end

            it { is_expected.to be_a(Dependabot::DependencyFile) }
            its(:content) { is_expected.to eq(contents) }
            its(:directory) { is_expected.to eq(directory) }
          end
        end
      end
    end

    describe "#clone_repo_contents" do
      subject(:clone_repo_contents) do
        file_fetcher_instance.clone_repo_contents
      end

      let(:repo) do
        "dependabot-fixtures/go-modules-app"
      end

      it "clones the repo" do
        clone_repo_contents
        expect(`ls #{repo_contents_path}`).to include("README")
      end

      context "with a branch name including bash command" do
        let(:branch) do
          "\"$(time)\""
        end

        it "clones the repo with branch checked out" do
          clone_repo_contents
          expect(`ls #{repo_contents_path}`).to include("time.md")
        end
      end

      context "when the repo can't be found" do
        let(:repo) do
          "dependabot-fixtures/not-found"
        end

        it "raises a not found error" do
          expect { clone_repo_contents }.to raise_error(Dependabot::RepoNotFound)
        end
      end

      context "when the branch can't be found" do
        let(:branch) do
          "notfound"
        end

        it "raises a not found error" do
          expect { clone_repo_contents }.to raise_error(Dependabot::BranchNotFound)
        end
      end

      context "when the submodule can't be reached" do
        let(:repo) do
          "dependabot-fixtures/go-modules-app-with-inaccessible-submodules"
        end
        let(:branch) do
          "with-git-urls"
        end

        it "does not raise an error" do
          clone_repo_contents
          expect(`ls #{repo_contents_path}`).to include("README")
        end
      end

      context "when the repo exceeds available disk space" do
        it "raises an out of disk error" do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "fatal: write error: No space left on device",
                error_context: {}
              )
            )

          expect { clone_repo_contents }.to raise_error(Dependabot::OutOfDisk)
        end
      end

      context "when a retryable error occurs" do
        let(:retryable_error) do
          proc {
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "The requested URL returned error: 429",
              error_context: {}
            )
          }
        end

        before do
          allow(file_fetcher_instance).to receive(:sleep)
          allow(Dependabot::SharedHelpers)
            .to receive(:with_git_configured)
            .and_yield
        end

        it "retries once" do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
            .and_invoke(
              retryable_error,
              proc { "" }
            )

          expect { clone_repo_contents }.not_to raise_error
          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).thrice
          expect(file_fetcher_instance).to have_received(:sleep).once
        end

        it "retries up to 5 times" do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
            .and_invoke(
              retryable_error,
              retryable_error,
              retryable_error,
              retryable_error,
              retryable_error,
              retryable_error
            )

          expect { clone_repo_contents }.to raise_error(Dependabot::RepoNotFound)
          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).exactly(6).times
          expect(file_fetcher_instance).to have_received(:sleep).exactly(5).times
        end

        it "doesn't retry a non-retryable error" do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "This is not a retryable error",
                error_context: {}
              )
            )

          expect { clone_repo_contents }.to raise_error(Dependabot::RepoNotFound)
          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
          expect(file_fetcher_instance).not_to have_received(:sleep)
        end
      end
    end
  end

  context "with submodules" do
    let(:repo) { "dependabot-fixtures/go-modules-app-with-git-submodules" }
    let(:repo_contents_path) { Dir.mktmpdir }
    let(:submodule_contents_path) { File.join(repo_contents_path, "examplelib") }

    after { FileUtils.rm_rf(repo_contents_path) }

    describe "#clone_repo_contents" do
      it "clones submodules by default" do
        file_fetcher_instance.clone_repo_contents

        expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
      end

      context "with a source commit" do
        let(:source_commit) { "5c7e92a4860382fd31336872f0fe79a848669c4d" }

        it "fetches/reset submodules by default" do
          file_fetcher_instance.clone_repo_contents

          expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
        end
      end

      context "when there's a submodule" do
        let(:child_class) do
          Class.new(described_class) do
            def self.required_files_in?(filenames)
              filenames.include?("go.mod")
            end

            def self.required_files_message
              "Repo must contain a go.mod."
            end

            private

            def fetch_files
              [fetch_file_from_host("go.mod")]
            end
          end
        end

        it "clones submodules" do
          file_fetcher_instance.clone_repo_contents

          expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
        end

        context "with a source commit" do
          let(:source_commit) { "5c7e92a4860382fd31336872f0fe79a848669c4d" }

          it "fetches/resets submodules if necessary" do
            file_fetcher_instance.clone_repo_contents

            expect(`ls -1 #{submodule_contents_path}`.split).to include("go.mod")
          end
        end
      end
    end
  end
end
