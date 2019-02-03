# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/source"
require "dependabot/file_fetchers/base"

RSpec.describe Dependabot::FileFetchers::Base do
  let(:source) do
    Dependabot::Source.new(
      provider: provider,
      repo: repo,
      directory: directory,
      branch: branch
    )
  end
  let(:provider) { "github" }
  let(:repo) { "gocardless/bump" }
  let(:directory) { "/" }
  let(:branch) { nil }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

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
    child_class.new(source: source, credentials: credentials)
  end

  describe "#commit" do
    subject(:commit) { file_fetcher_instance.commit }

    context "with a GitHub source" do
      let(:url) { "https://api.github.com/repos/#{repo}" }

      before do
        stub_request(:get, url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: fixture("github", "bump_repo.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, url + "/git/refs/heads/master").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: fixture("github", "ref.json"),
                    headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd") }

      context "when the repo is empty" do
        before do
          stub_request(:get, url + "/git/refs/heads/master").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 409,
                      body: fixture("github", "git_repo_empty.json"),
                      headers: { "content-type" => "application/json" })
        end

        it { is_expected.to be_nil }
      end

      context "with a target branch" do
        let(:branch) { "my_branch" }

        before do
          stub_request(:get, url + "/git/refs/heads/my_branch").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 200,
                      body: fixture("github", "ref_my_branch.json"),
                      headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("bb218f56b14c9653891f9e74264a383fa43fefbd") }

        context "that can't be found" do
          before do
            stub_request(:get, url + "/git/refs/heads/my_branch").
              with(headers: { "Authorization" => "token token" }).
              to_return(status: 404,
                        headers: { "content-type" => "application/json" })
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }.
              to raise_error(Dependabot::BranchNotFound) do |error|
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
        stub_request(:get, project_url).
          to_return(status: 200,
                    body: fixture("gitlab", "bump_repo.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, branch_url).
          to_return(status: 200,
                    body: fixture("gitlab", "master_branch.json"),
                    headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("f7dd067490fe57505f7226c3b54d3127d2f7fd46") }

      context "with a target branch" do
        let(:branch) { "my_branch" }
        let(:branch_url) { project_url + "/repository/branches/my_branch" }

        before do
          stub_request(:get, branch_url).
            to_return(status: 200,
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
        stub_request(:get, repo_url).
          to_return(status: 200,
                    body: fixture("bitbucket", "bump_repo.json"),
                    headers: { "content-type" => "application/json" })
        stub_request(:get, branch_url).
          to_return(status: 200,
                    body: fixture("bitbucket", "default_branch.json"),
                    headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("0fd7bb2494e8cc11c71c05f8f12deafa6b41fb37") }

      context "with a target branch" do
        let(:branch) { "my_branch" }
        let(:branch_url) { repo_url + "/refs/branches/my_branch" }

        before do
          stub_request(:get, branch_url).
            to_return(status: 200,
                      body: fixture("bitbucket", "other_branch.json"),
                      headers: { "content-type" => "application/json" })
        end

        it { is_expected.to eq("4c2ea65f2eb932c438557cb6ec29b984794c6108") }
      end
    end
  end

  describe "#files" do
    subject(:files) { file_fetcher_instance.files }
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    end

    context "with a GitHub source" do
      its(:length) { is_expected.to eq(1) }

      let(:url) { "https://api.github.com/repos/#{repo}/contents/" }
      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
                    body: fixture("github", "gemfile_content.json"),
                    headers: { "content-type" => "application/json" })
      end

      describe "the file" do
        subject { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("octokit") }

        context "when there are non-ASCII characters" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "gemfile_content_non_ascii.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          its(:content) { is_expected.to eq("öäöä") }
        end

        context "when the file is a directory" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }.
              to raise_error(Dependabot::DependencyFileNotFound) do |error|
                expect(error.file_path).to eq("/requirements.txt")
              end
          end
        end
      end

      context "with a directory specified" do
        context "that ends in a slash" do
          let(:directory) { "app/" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "that begins with a slash" do
          let(:directory) { "/app" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "that includes a slash" do
          let(:directory) { "a/pp" }
          let(:url) { "https://api.github.com/repos/#{repo}/contents/a/pp/" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound) do |error|
              expect(error.file_path).to eq("/requirements.txt")
            end
        end
      end

      context "when a dependency file returns a symlink" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "symlinked_file_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "symlinked/requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("octokit") }
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
          stub_request(:get, url + "some/dir/req.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
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

        context "that is in a submodule (shallow)" do
          before do
            stub_request(:get, url + "some/dir/req.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            submodule_details =
              fixture("github", "submodule.json").
              gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
            stub_request(:get, url + "some/dir?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: submodule_details,
                headers: { "content-type" => "application/json" }
              )

            sub_url = "https://api.github.com/repos/dependabot/"\
                      "manifesto/contents/"
            stub_request(:get, sub_url + "?ref=sha2").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "req.txt?ref=sha2").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }.
              to raise_error(Dependabot::DependencyFileNotFound) do |error|
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

        context "that is in a submodule (deep)" do
          before do
            stub_request(:get, url + "some/dir/req.txt?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            stub_request(:get, url + "some/dir?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            submodule_details =
              fixture("github", "submodule.json").
              gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
            stub_request(:get, url + "some?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: submodule_details,
                headers: { "content-type" => "application/json" }
              )

            sub_url = "https://api.github.com/repos/dependabot/"\
                      "manifesto/contents/"
            stub_request(:get, sub_url + "?ref=sha2").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: "[]",
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "dir?ref=sha2").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "business_files.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, sub_url + "dir/req.txt?ref=sha2").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "gemfile_content.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "raises a custom error" do
            expect { file_fetcher_instance.files }.
              to raise_error(Dependabot::DependencyFileNotFound) do |error|
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
          "https://api.github.com/repos/#{repo}/git/blobs/"\
          "88b4e0a1c8093fae2b4fa52534035f9f85ed0956"
        end
        before do
          stub_request(:get, url + "requirements.txt?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 403,
              body: fixture("github", "file_too_large.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_python.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, blob_url).
            with(headers: { "Authorization" => "token token" }).
            to_return(
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
            stub_request(:get, url.gsub(%r{/$}, "") + "?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "contents_python.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
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
        stub_request(:get, url + "requirements.txt?ref=sha").
          to_return(status: 200,
                    body: fixture("gitlab", "gemfile_content.json"),
                    headers: { "content-type" => "application/json" })
      end

      its(:length) { is_expected.to eq(1) }

      describe "the file" do
        subject { files.find { |file| file.name == "requirements.txt" } }

        it { is_expected.to be_a(Dependabot::DependencyFile) }
        its(:content) { is_expected.to include("octokit") }

        context "when there are non-ASCII characters" do
          before do
            stub_request(:get, url + "requirements.txt?ref=sha").
              to_return(
                status: 200,
                body: fixture("gitlab", "gemfile_content_non_ascii.json"),
                headers: { "content-type" => "application/json" }
              )
          end

          its(:content) { is_expected.to eq("öäöä") }
        end
      end

      context "with a directory specified" do
        let(:file_fetcher_instance) do
          child_class.new(source: source, credentials: credentials)
        end

        context "that ends in a slash" do
          let(:directory) { "app/" }
          let(:url) { project_url + "/repository/files/app%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "that begins with a slash" do
          let(:directory) { "/app" }
          let(:url) { project_url + "/repository/files/app%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end

        context "that includes a slash" do
          let(:directory) { "a/pp" }
          let(:url) { project_url + "/repository/files/a%2Fpp%2F" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).
              to have_requested(:get, url + "requirements.txt?ref=sha")
          end
        end
      end

      context "when a dependency file can't be found" do
        before do
          stub_request(:get, url + "requirements.txt?ref=sha").
            to_return(
              status: 404,
              body: fixture("gitlab", "not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound) do |error|
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
        stub_request(:get, url).
          to_return(status: 200,
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

        context "that ends in a slash" do
          let(:directory) { "app/" }
          let(:url) { repo_url + "/src/sha/app/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "that begins with a slash" do
          let(:directory) { "/app" }
          let(:url) { repo_url + "/src/sha/app/requirements.txt" }

          it "hits the right GitHub URL" do
            files
            expect(WebMock).to have_requested(:get, url)
          end
        end

        context "that includes a slash" do
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
          stub_request(:get, url).
            to_return(
              status: 404,
              body: fixture("bitbucket", "file_not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a custom error" do
          expect { file_fetcher_instance.files }.
            to raise_error(Dependabot::DependencyFileNotFound) do |error|
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
          stub_request(:get, repo_contents_url).
            to_return(status: 200,
                      body: fixture("bitbucket", "business_files.json"),
                      headers: { "content-type" => "application/json" })
        end

        its(:length) { is_expected.to eq(1) }

        describe "the file" do
          subject { files.find { |file| file.name == "requirements.txt" } }

          it { is_expected.to be_a(Dependabot::DependencyFile) }
          its(:content) { is_expected.to include("required_rubygems_version") }
        end

        context "that can't be found" do
          before do
            stub_request(:get, repo_contents_url).
              to_return(status: 200,
                        body: fixture("bitbucket", "no_files.json"),
                        headers: { "content-type" => "application/json" })
          end

          its(:length) { is_expected.to eq(0) }
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

    context "with an interesting filename" do
      let(:file_fetcher_instance) do
        child_class.new(source: source, credentials: credentials)
      end

      before do
        stub_request(:get, file_url).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 200,
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
end
