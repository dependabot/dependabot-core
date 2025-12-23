# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/lean/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Lean::FileFetcher do
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
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:json_header) { { "content-type" => "application/json" } }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "returns true if lean-toolchain is present" do
      expect(described_class.required_files_in?(["lean-toolchain"])).to be true
      expect(described_class.required_files_in?(["README.md", "lean-toolchain"])).to be true
    end

    it "returns false if lean-toolchain is absent" do
      expect(described_class.required_files_in?(["README.md"])).to be false
      expect(described_class.required_files_in?([])).to be false
    end
  end

  describe "#fetch_files" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    end

    context "with a lean-toolchain file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_lean_toolchain.json"),
            headers: json_header
          )

        stub_request(:get, url + "lean-toolchain?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_lean_toolchain_file.json"),
            headers: json_header
          )
      end

      it "fetches the lean-toolchain file" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).to eq(["lean-toolchain"])
      end
    end

    context "without a lean-toolchain file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: "[]",
            headers: json_header
          )
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
