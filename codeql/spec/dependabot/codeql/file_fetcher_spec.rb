# typed: false
# frozen_string_literal: true

require "base64"
require "spec_helper"
require "dependabot/source"
require "dependabot/codeql/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Codeql::FileFetcher do
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }]
  end
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/example/codeql-packs/contents/" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "example/codeql-packs", directory: directory)
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: nil)
  end

  let(:qlpack_body) do
    { name: "qlpack.yml", path: "qlpack.yml", type: "file", size: 42,
      content: Base64.encode64("name: example/queries\n") }.to_json
  end
  let(:lockfile_body) do
    { name: "codeql-pack.lock.yml", path: "codeql-pack.lock.yml", type: "file", size: 20,
      content: Base64.encode64("dependencies: {}\n") }.to_json
  end

  let(:directory_listing) do
    [
      { name: "qlpack.yml", path: "qlpack.yml", type: "file", size: 42 },
      { name: "codeql-pack.lock.yml", path: "codeql-pack.lock.yml", type: "file", size: 20 }
    ].to_json
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, url + "?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(status: 200, body: directory_listing, headers: { "content-type" => "application/json" })

    stub_request(:get, url + "qlpack.yml?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(status: 200, body: qlpack_body, headers: { "content-type" => "application/json" })

    stub_request(:get, url + "codeql-pack.lock.yml?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(status: 200, body: lockfile_body, headers: { "content-type" => "application/json" })
  end

  it_behaves_like "a dependency file fetcher"

  context "with a qlpack.yml and a lockfile" do
    it "fetches both files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to contain_exactly("qlpack.yml", "codeql-pack.lock.yml")
    end
  end

  context "with a qlpack.yml but no lockfile" do
    let(:directory_listing) do
      [{ name: "qlpack.yml", path: "qlpack.yml", type: "file", size: 42 }].to_json
    end

    it "fetches only the manifest" do
      expect(file_fetcher_instance.files.map(&:name)).to contain_exactly("qlpack.yml")
    end
  end

  context "without a qlpack.yml" do
    let(:directory_listing) do
      [{ name: "README.md", path: "README.md", type: "file", size: 10 }].to_json
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
