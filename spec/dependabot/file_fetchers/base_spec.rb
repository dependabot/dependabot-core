# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/file_fetchers/ruby/bundler"

RSpec.describe Dependabot::FileFetchers::Base do
  let(:repo) { "gocardless/bump" }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

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
        [fetch_file_from_github("requirements.txt")]
      end
    end
  end
  let(:file_fetcher_instance) do
    child_class.new(repo: repo, github_client: github_client)
  end

  describe "#commit" do
    subject(:commit) { file_fetcher_instance.commit }
    let(:url) { "https://api.github.com/repos/#{repo}" }

    before do
      stub_request(:get, url).
        to_return(status: 200,
                  body: fixture("github", "bump_repo.json"),
                  headers: { "content-type" => "application/json" })
      stub_request(:get, url + "/git/refs/heads/master").
        to_return(status: 200,
                  body: fixture("github", "ref.json"),
                  headers: { "content-type" => "application/json" })
    end

    it { is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd") }

    context "with a target branch" do
      let(:file_fetcher_instance) do
        child_class.new(
          repo: repo,
          github_client: github_client,
          target_branch: "my_branch"
        )
      end

      before do
        stub_request(:get, url + "/git/refs/heads/my_branch").
          to_return(status: 200,
                    body: fixture("github", "ref_my_branch.json"),
                    headers: { "content-type" => "application/json" })
      end

      it { is_expected.to eq("bb218f56b14c9653891f9e74264a383fa43fefbd") }
    end
  end

  describe "#files" do
    subject(:files) { file_fetcher_instance.files }
    let(:url) { "https://api.github.com/repos/#{repo}/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
      stub_request(:get, url + "requirements.txt?ref=sha").
        to_return(status: 200,
                  body: fixture("github", "gemfile_content.json"),
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
            to_return(status: 200,
                      body: fixture("github", "gemfile_content_non_ascii.json"),
                      headers: { "content-type" => "application/json" })
        end

        its(:content) { is_expected.to eq("öäöä") }
      end
    end

    context "with a directory specified" do
      let(:file_fetcher_instance) do
        child_class.new(
          repo: repo,
          github_client: github_client,
          directory: directory
        )
      end

      context "that ends in a slash" do
        let(:directory) { "app/" }
        let(:url) { "https://api.github.com/repos/#{repo}/contents/app/" }

        it "hits the right GitHub URL" do
          files
          expect(WebMock).
            to have_requested(:get, url + "requirements.txt?ref=sha")
        end
      end

      context "that begins in a slash" do
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

    context "with an interesting filename" do
      let(:file_fetcher_instance) do
        child_class.new(
          repo: repo,
          github_client: github_client,
          directory: directory
        )
      end

      before do
        stub_request(:get, file_url).
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
              [fetch_file_from_github("./some/file")]
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
              [fetch_file_from_github("../some/file")]
            end
          end
        end

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, file_url)
        end
      end
    end

    context "when a dependency file can't be found" do
      before do
        stub_request(:get, url + "requirements.txt?ref=sha").
          to_return(status: 404)
      end

      it "raises a custom error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.file_name).to eq("requirements.txt")
          end
      end
    end
  end
end
