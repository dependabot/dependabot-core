# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/file_fetchers"
require "dependabot/devbox/file_fetcher"

RSpec.describe Dependabot::Devbox::FileFetcher do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "test/repo",
      directory: "/"
    )
  end
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

  it "is registered for the devbox package manager" do
    expect(Dependabot::FileFetchers.for_package_manager("devbox")).to eq(described_class)
  end

  describe ".required_files_in?" do
    it "returns true when devbox.json is present" do
      expect(described_class.required_files_in?(%w(devbox.json))).to be true
    end

    it "returns false when devbox.json is absent" do
      expect(described_class.required_files_in?(%w(devbox.lock package.json))).to be false
    end
  end

  describe ".required_files_message" do
    it "mentions devbox.json" do
      expect(described_class.required_files_message).to include("devbox.json")
    end
  end

  describe "#files" do
    let(:repo_contents_path) { build_tmp_repo("devbox/basic") }
    let(:file_fetcher_instance) do
      described_class.new(
        source: source,
        credentials: credentials,
        repo_contents_path: repo_contents_path
      )
    end

    before do
      allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: true)
      allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
    end

    after { FileUtils.rm_rf(repo_contents_path) }

    it "fetches the manifest and the lockfile" do
      expect(file_fetcher_instance.files.map(&:name)).to contain_exactly("devbox.json", "devbox.lock")
    end

    context "when there is no lockfile" do
      before { FileUtils.rm_f(File.join(repo_contents_path, "devbox.lock")) }

      it "fetches just the manifest" do
        expect(file_fetcher_instance.files.map(&:name)).to contain_exactly("devbox.json")
      end
    end

    context "when beta ecosystems are not enabled" do
      before { allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false) }

      it "raises DependencyFileNotFound" do
        expect { file_fetcher_instance.files }.to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end
end
