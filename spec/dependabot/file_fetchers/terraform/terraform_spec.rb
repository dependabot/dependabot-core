# frozen_string_literal: true

require "dependabot/file_fetchers/terraform/terraform"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Terraform::Terraform do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a Terraform file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_terraform_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      %w(main.tf outputs.tf variables.tf).each do |nm|
        stub_request(:get, File.join(url, "#{nm}?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_terraform_file.json"),
            headers: { "content-type" => "application/json" }
          )
      end
    end

    it "fetches the Terraform files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(main.tf outputs.tf variables.tf))
    end
  end

  context "with a directory that doesn't exist" do
    let(:directory) { "/non/existant" }

    before do
      stub_request(:get, url + "non/existant?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404,
          body: fixture("github", "not_found.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
