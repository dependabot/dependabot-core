require "spec_helper"
require "./app/dependency_file"
require "./app/dependency_file_fetchers/node_dependency_file_fetcher"

RSpec.describe DependencyFileFetchers::NodeDependencyFileFetcher do
  let(:file_fetcher) { described_class.new(repo) }
  let(:repo) { "gocardless/bump" }

  describe "#files" do
    subject(:files) { file_fetcher.files }
    let(:url) { "https://api.github.com/repos/#{repo}/contents/" }
    before do
      stub_request(:get, url + "package.json").
        to_return(status: 200,
                  body: fixture("github", "package_json_content.json"),
                  headers: { "content-type" => "application/json" })
      stub_request(:get, url + "npm-shrinkwrap.json").
        to_return(status: 200,
                  body: fixture("github", "npm_shrinkwrap_json_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(2) }

    describe "the package.json" do
      subject { files.find { |file| file.name == "package.json" } }

      it { is_expected.to be_a(DependencyFile) }
      its(:content) { is_expected.to include("lodash") }
    end

    describe "the npm-shrinkwrap.json" do
      subject { files.find { |file| file.name == "npm-shrinkwrap.json" } }

      it { is_expected.to be_a(DependencyFile) }
      its(:content) { is_expected.to include("lodash") }
    end
  end
end
