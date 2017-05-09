# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/repo"
require "bump/dependency_file_fetchers/ruby"

RSpec.describe Bump::DependencyFileFetchers::Base do
  let(:file_fetcher) do
    described_class.new(repo: repo, github_client: github_client)
  end
  let(:repo) do
    Bump::Repo.new(name: "gocardless/bump", language: nil, commit: nil)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  describe "#fetch_file_from_github" do
    subject(:fetch_file_from_github) do
      file_fetcher.send(:fetch_file_from_github, "file")
    end

    let(:url) { "https://api.github.com/repos/#{repo.name}/contents/" }
    before do
      stub_request(:get, url + "file").
        to_return(status: 200,
                  body: fixture("github", "gemfile_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    it { is_expected.to be_a(Bump::DependencyFile) }
    its(:content) { is_expected.to include("octokit") }

    context "with a directory specified" do
      let(:file_fetcher) do
        described_class.new(
          repo: repo,
          github_client: github_client,
          directory: directory
        )
      end

      context "that ends in a slash" do
        let(:directory) { "app/" }
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/app/" }

        it "hits the right GitHub URL" do
          fetch_file_from_github
          expect(WebMock).to have_requested(:get, url + "file")
        end
      end

      context "that begins in a slash" do
        let(:directory) { "/app" }
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/app/" }

        it "hits the right GitHub URL" do
          fetch_file_from_github
          expect(WebMock).to have_requested(:get, url + "file")
        end
      end

      context "that includes a slash" do
        let(:directory) { "a/pp" }
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/a/pp/" }

        it "hits the right GitHub URL" do
          fetch_file_from_github
          expect(WebMock).to have_requested(:get, url + "file")
        end
      end
    end

    context "when a dependency file can't be found" do
      before { stub_request(:get, url + "file").to_return(status: 404) }

      it "raises a custom error" do
        expect { fetch_file_from_github }.
          to raise_error(Bump::DependencyFileNotFound) do |error|
            expect(error.file_name).to eq("file")
            expect(error.directory).to eq("/")
          end
      end
    end
  end
end
