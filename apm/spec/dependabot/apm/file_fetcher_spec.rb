# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/apm/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Apm::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/agent-repo",
      directory: "/"
    )
  end
  let(:url) { "https://api.github.com/repos/example/agent-repo/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: nil)
  end

  before do
    allow(file_fetcher_instance)
      .to receive_messages(commit: "sha", allow_beta_ecosystems?: true)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "requires an apm.yml file" do
      expect(described_class.required_files_in?(["apm.yml"])).to be(true)
      expect(described_class.required_files_in?(["package.json"])).to be(false)
    end
  end

  describe "#fetch_files" do
    subject(:fetched_files) { file_fetcher_instance.files }

    before do
      stub_request(:get, url + "apm.yml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "apm_yml.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "with a manifest and a lockfile" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_apm_repo.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "apm.lock.yaml?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "apm_lock.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the manifest and the lockfile" do
        expect(fetched_files.map(&:name)).to contain_exactly("apm.yml", "apm.lock.yaml")
      end

      it "marks the lockfile as a support file" do
        lockfile = fetched_files.find { |f| f.name == "apm.lock.yaml" }
        expect(lockfile.support_file?).to be(true)
      end
    end

    context "without a lockfile" do
      before do
        stub_request(:get, url + "?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "contents_apm_repo_no_lock.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches just the manifest" do
        expect(fetched_files.map(&:name)).to contain_exactly("apm.yml")
      end
    end
  end

  describe "#ecosystem_versions" do
    subject(:ecosystem_versions) { file_fetcher_instance.ecosystem_versions }

    before do
      stub_request(:get, url + "apm.yml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "apm_yml.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "contents_apm_repo.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "apm.lock.yaml?ref=sha")
        .with(headers: { "Authorization" => "token token" })
        .to_return(
          status: 200,
          body: fixture("github", "apm_lock.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "reports the apm version from the lockfile" do
      expect(ecosystem_versions).to eq(package_managers: { "apm" => "0.4.2" })
    end
  end

  context "when the beta ecosystems flag is disabled" do
    before do
      allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
    end

    it "raises a DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
