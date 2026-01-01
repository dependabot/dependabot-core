# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/opam/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Opam::FileFetcher do
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
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "ocaml/example",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: nil)
  end
  let(:url) { "https://api.github.com/repos/ocaml/example/contents/" }
  let(:json_header) { { "content-type" => "application/json" } }

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    VCR.turn_off!

    stub_request(:get, url + "?ref=sha")
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_ocaml_repo.json"),
        headers: json_header
      )

    stub_request(:get, File.join(url, "example.opam?ref=sha"))
      .with(headers: { "Authorization" => "token token" })
      .to_return(
        status: 200,
        body: fixture("github", "contents_ocaml_opam_file.json"),
        headers: json_header
      )
  end

  after do
    VCR.turn_on!
  end

  it_behaves_like "a dependency file fetcher"

  it "fetches the opam file" do
    expect(file_fetcher_instance.files.count).to be >= 1
    expect(file_fetcher_instance.files.map(&:name)).to include("example.opam")
  end
end
