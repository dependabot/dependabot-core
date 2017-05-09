# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/repo"
require "bump/dependency_file_fetchers/java_script"

RSpec.describe Bump::DependencyFileFetchers::JavaScript do
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
      stub_request(:get, url + "package.json").
        to_return(status: 200,
                  body: fixture("github", "package_json_content.json"),
                  headers: { "content-type" => "application/json" })
      stub_request(:get, url + "yarn.lock").
        to_return(status: 200,
                  body: fixture("github", "yarn_lock_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(2) }

    describe "the package.json" do
      subject { files.find { |file| file.name == "package.json" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("lodash") }
    end

    describe "the yarn.lock" do
      subject { files.find { |file| file.name == "yarn.lock" } }

      it { is_expected.to be_a(Bump::DependencyFile) }
      its(:content) { is_expected.to include("lodash") }
    end
  end
end
