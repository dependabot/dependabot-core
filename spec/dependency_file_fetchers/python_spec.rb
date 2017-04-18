# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/repo"
require "bump/dependency_file_fetchers/python"

RSpec.describe Bump::DependencyFileFetchers::Python do
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
      stub_request(:get, url + "requirements.txt").
        to_return(status: 200,
                  body: fixture("github", "requirements_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(1) }

    describe "the requirements.txt" do
      subject { files.find { |file| file.name == "requirements.txt" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("psycopg2") }
    end
  end
end
