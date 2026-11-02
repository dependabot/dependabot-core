# typed: false
# frozen_string_literal: true

require "base64"
require "json"

require "spec_helper"
require "dependabot/nimble/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Nimble::FileFetcher do
  let(:credentials) do
    [Dependabot::Credential.new(
      { "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "token" }
    )]
  end
  let(:url) { "https://api.github.com/repos/example/repo/contents/" }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/") }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: nil)
  end
  let(:beta_enabled) { true }

  def listing(*names)
    names.map do |name|
      { "name" => name, "path" => name, "type" => "file", "size" => 10,
        "download_url" => "https://example.test/#{name}" }
    end
  end

  def stub_listing(*names)
    stub_request(:get, url + "?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(status: 200, body: JSON.generate(listing(*names)), headers: { "content-type" => "application/json" })
  end

  def stub_file(name, content)
    stub_request(:get, url + "#{name}?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: JSON.generate(
          { "name" => name, "path" => name, "type" => "file",
            "content" => Base64.encode64(content), "encoding" => "base64" }
        ),
        headers: { "content-type" => "application/json" }
      )
  end

  before do
    allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: beta_enabled)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "wants a .nimble file" do
      expect(described_class.required_files_in?(%w(README.md example.nimble))).to be(true)
      expect(described_class.required_files_in?(%w(README.md nimble.lock))).to be(false)
    end
  end

  context "with a package file" do
    before do
      stub_listing("README.md", "example.nimble")
      stub_file("example.nimble", 'requires "chronos >= 4.0"')
    end

    it "fetches the package file" do
      expect(file_fetcher_instance.files.map(&:name)).to eq(%w(example.nimble))
    end
  end

  context "without a package file" do
    before { stub_listing("README.md") }

    it "raises DependencyFileNotFound" do
      expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "when beta ecosystems are not enabled" do
    let(:beta_enabled) { false }

    it "raises DependencyFileNotFound and says why" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound, /beta/)
    end
  end
end
