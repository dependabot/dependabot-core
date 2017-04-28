# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/repo"
require "bump/dependency_file_fetchers/ruby"

RSpec.describe Bump::DependencyFileFetchers::Ruby do
  let(:file_fetcher) do
    described_class.new(repo: repo, github_client: github_client)
  end
  let(:repo) do
    Bump::Repo.new(name: "gocardless/bump", language: nil, commit: nil)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  describe "#files" do
    subject(:files) { file_fetcher.files }
    let(:url) { "https://api.github.com/repos/#{repo.name}/contents/" }
    before do
      stub_request(:get, url + "Gemfile").
        to_return(status: 200,
                  body: fixture("github", "gemfile_content.json"),
                  headers: { "content-type" => "application/json" })
      stub_request(:get, url + "Gemfile.lock").
        to_return(status: 200,
                  body: fixture("github", "gemfile_lock_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(2) }

    describe "the Gemfile" do
      subject { files.find { |file| file.name == "Gemfile" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("octokit") }
    end

    describe "the Gemfile.lock" do
      subject { files.find { |file| file.name == "Gemfile.lock" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("octokit") }
    end

    context "when a dependency file can't be found" do
      before { stub_request(:get, url + "Gemfile").to_return(status: 404) }

      it "raises a custom error" do
        expect { file_fetcher.files }.
          to raise_error(Bump::DependencyFileNotFound)
      end
    end
  end
end
