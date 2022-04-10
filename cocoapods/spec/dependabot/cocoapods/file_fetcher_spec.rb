# frozen_string_literal: true

require "spec_helper"
require "dependabot/cocoapods/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::CocoaPods::FileFetcher do
  it_behaves_like "a dependency file fetcher"

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
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:json_header) { { "content-type" => "application/json" } }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  before do
    stub_request(:get, "#{url}?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cocoapods_repo.json"),
        headers: json_header
      )

    stub_request(:get, "#{url}Podfile?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cocoapods_podfile.json"),
        headers: json_header
      )

    stub_request(:get, "#{url}Podfile.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_cocoapods_lockfile.json"),
        headers: json_header
      )
  end

  it "fetches the Podfile and Podfile.lock" do
    expect(file_fetcher_instance.files.count).to eq(2)
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(Podfile Podfile.lock))
  end

  context "without a lockfile" do
    before do
      stub_request(:get, "#{url}Podfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "without a Podfile" do
    before do
      stub_request(:get, "#{url}Podfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404, headers: json_header)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
