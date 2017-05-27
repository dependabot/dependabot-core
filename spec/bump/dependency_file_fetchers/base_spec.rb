# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/repo"
require "bump/dependency_file_fetchers/ruby/bundler"

RSpec.describe Bump::DependencyFileFetchers::Base do
  let(:repo) { Bump::Repo.new(name: "gocardless/bump", commit: nil) }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  let(:child_class) do
    Class.new(described_class) do
      def self.required_files
        ["Gemfile"]
      end
    end
  end
  let(:file_fetcher_instance) do
    child_class.new(repo: repo, github_client: github_client)
  end

  describe "#files" do
    subject(:files) { file_fetcher_instance.files }
    let(:url) { "https://api.github.com/repos/#{repo.name}/contents/" }
    before do
      stub_request(:get, url + "Gemfile").
        to_return(status: 200,
                  body: fixture("github", "gemfile_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(1) }

    describe "the file" do
      subject { files.find { |file| file.name == "Gemfile" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("octokit") }
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
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/app/" }

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, url + "Gemfile")
        end
      end

      context "that begins in a slash" do
        let(:directory) { "/app" }
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/app/" }

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, url + "Gemfile")
        end
      end

      context "that includes a slash" do
        let(:directory) { "a/pp" }
        let(:url) { "https://api.github.com/repos/#{repo.name}/contents/a/pp/" }

        it "hits the right GitHub URL" do
          files
          expect(WebMock).to have_requested(:get, url + "Gemfile")
        end
      end
    end

    context "when a dependency file can't be found" do
      before { stub_request(:get, url + "Gemfile").to_return(status: 404) }

      it "raises a custom error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Bump::DependencyFileNotFound) do |error|
            expect(error.file_name).to eq("Gemfile")
          end
      end
    end
  end
end
