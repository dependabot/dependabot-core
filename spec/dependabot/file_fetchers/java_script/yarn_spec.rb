# frozen_string_literal: true

require "dependabot/file_fetchers/java_script/yarn"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::JavaScript::Yarn do
  it_behaves_like "a dependency file fetcher"

  context "with a path dependency" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "package.json?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "package_json_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "yarn.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "yarn_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "with a bad package.json" do
      before do
        stub_request(:get, url + "package.json?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("package.json")
          end
      end
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, url + "deps/etag/package.json?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches package.json from path dependency" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("deps/etag/package.json")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + "deps/etag/package.json?ref=sha").
          to_return(status: 404)
      end

      it "raises a PathDependenciesNotReachable error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: " \
            "etag"
          )
      end
    end
  end
end
