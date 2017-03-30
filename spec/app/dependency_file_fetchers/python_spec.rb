# frozen_string_literal: true
require "spec_helper"
require "./app/dependency_file_fetchers/python"

RSpec.describe DependencyFileFetchers::Python do
  let(:file_fetcher) { described_class.new(repo) }
  let(:repo) { "gocardless/bump" }

  describe "#files" do
    subject(:files) { file_fetcher.files }
    let(:url) { "https://api.github.com/repos/#{repo}/contents/" }
    before do
      stub_request(:get, url + "requirements.txt").
        to_return(status: 200,
                  body: fixture("github", "requirements_content.json"),
                  headers: { "content-type" => "application/json" })
    end

    its(:length) { is_expected.to eq(1) }

    describe "the requirements.txt" do
      subject { files.find { |file| file.name == "requirements.txt" } }

      it { is_expected.to be_a(DependencyFile) }
      its(:content) { is_expected.to include("psycopg2") }
    end
  end
end
