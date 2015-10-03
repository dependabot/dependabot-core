require "spec_helper"
require "bumper/dependency_file"
require "bumper/dependency_file_fetchers/ruby_dependency_file_fetcher"

RSpec.describe DependencyFileFetchers::RubyDependencyFileFetcher do
  let(:file_fetcher) { described_class.new(repo) }
  let(:repo) { "gocardless/bump" }

  describe "individual dependency files" do
    let(:url) { "https://api.github.com/repos/#{repo}/contents/#{file_name}" }
    before do
      stub_request(:get, url).
        to_return(status: 200,
                  body: github_response,
                  headers: { "content-type" => "application/json" })
    end

    describe "#gemfile" do
      let(:file_name) { "Gemfile" }
      let(:github_response) { fixture("github", "gemfile_content.json") }

      subject { file_fetcher.gemfile }

      it { is_expected.to be_a(DependencyFile) }
      its(:name) { is_expected.to eq("Gemfile") }
      its(:content) { is_expected.to include("octokit") }
    end

    describe "#gemfile.lock" do
      let(:file_name) { "Gemfile.lock" }
      let(:github_response) { fixture("github", "gemfile_lock_content.json") }

      subject { file_fetcher.gemfile_lock }

      it { is_expected.to be_a(DependencyFile) }
      its(:name) { is_expected.to eq("Gemfile.lock") }
      its(:content) { is_expected.to include("octokit") }
    end
  end
end
