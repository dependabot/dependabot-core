# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/nix/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Nix::FileFetcher do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(T::Array[Dependabot::Credential]) }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  sig { returns(String) }
  let(:url) { github_url + "repos/example/repo/contents/" }
  sig { returns(String) }
  let(:github_url) { "https://api.github.com/" }
  sig { returns(String) }
  let(:directory) { "/" }
  sig { returns(Dependabot::Source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: directory
    )
  end
  sig { returns(Dependabot::Nix::FileFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  before do
    allow(file_fetcher_instance).to receive_messages(commit: "sha")
  end

  describe ".required_files_in?" do
    it "returns true when both flake.nix and flake.lock are present" do
      expect(described_class.required_files_in?(%w(flake.nix flake.lock))).to be true
    end

    it "returns false when only flake.nix is present" do
      expect(described_class.required_files_in?(%w(flake.nix))).to be false
    end

    it "returns false when only flake.lock is present" do
      expect(described_class.required_files_in?(%w(flake.lock))).to be false
    end

    it "returns false when neither file is present" do
      expect(described_class.required_files_in?(%w(package.json))).to be false
    end
  end

  describe "#fetch_files" do
    before do
      stub_request(:get, url + "flake.nix?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture_body("flake.nix"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "flake.lock?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture_body("flake.lock"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches both flake.nix and flake.lock" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).to match_array(%w(flake.nix flake.lock))
    end
  end

  private

  sig { params(filename: String).returns(String) }
  def fixture_body(filename)
    content = File.read(
      File.join(__dir__, "fixtures", filename)
    )
    {
      "name" => filename,
      "content" => Base64.encode64(content),
      "encoding" => "base64",
      "path" => filename
    }.to_json
  end
end
