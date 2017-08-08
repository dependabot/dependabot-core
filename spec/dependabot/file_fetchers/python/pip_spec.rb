# frozen_string_literal: true
require "dependabot/file_fetchers/python/pip"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Python::Pip do
  it_behaves_like "a dependency file fetcher"

  context "with a path-based dependency" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "requirements.txt?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "requirements_with_self_reference.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "that is fetchable" do
      before do
        stub_request(:get, url + "setup.py?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "setup_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the setup.py" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("setup.py")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + "setup.py?ref=sha").
          to_return(status: 404)
      end

      it "raises a PathDependenciesNotReachable error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: " \
            "setup.py"
          )
      end
    end
  end
end
