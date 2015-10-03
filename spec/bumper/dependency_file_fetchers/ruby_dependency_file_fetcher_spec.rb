require "spec_helper"
require "bumper/dependency_file"
require "bumper/dependency_file_fetchers/ruby_dependency_file_fetcher"

RSpec.describe DependencyFileFetchers::RubyDependencyFileFetcher do
  let(:file_fetcher) { described_class.new(repo) }
  let(:repo) { 'gocardless/bump' }
  let(:github_content_response) { fixture(File.join('github', 'gemfile_content.json')) }

  before do
    stub_request(:get, "https://api.github.com/repos/#{repo}/contents/Gemfile").
      to_return(status: 200,
                body: github_content_response,
                headers: { "content-type" => "application/json" })
  end

  describe "#gemfile" do
    subject { file_fetcher.gemfile }

    it { is_expected.to be_a(DependencyFile) }
    its(:name) { is_expected.to eq("Gemfile") }
    its(:content) { is_expected.to include("octokit") }
  end
end
