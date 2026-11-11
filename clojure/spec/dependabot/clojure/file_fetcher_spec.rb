# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clojure/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Clojure::FileFetcher do
  let(:source) { Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/") }
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
  let(:project_name) { "lein" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials, repo_contents_path: repo_contents_path)
  end

  before do
    allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: true)
  end

  after { FileUtils.rm_rf(repo_contents_path) }

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    it "accepts a project.clj or a deps.edn" do
      expect(described_class.required_files_in?(%w(project.clj))).to be(true)
      expect(described_class.required_files_in?(%w(deps.edn))).to be(true)
    end

    it "rejects other files" do
      expect(described_class.required_files_in?(%w(pom.xml))).to be(false)
    end
  end

  describe "#files" do
    subject(:files) { file_fetcher_instance.files }

    context "with a project.clj" do
      it "fetches it" do
        expect(files.map(&:name)).to eq(%w(project.clj))
      end
    end

    context "with a deps.edn" do
      let(:project_name) { "deps" }

      it "fetches it" do
        expect(files.map(&:name)).to eq(%w(deps.edn))
      end
    end

    context "with both files" do
      let(:project_name) { "lein_and_deps" }

      it "fetches both" do
        expect(files.map(&:name)).to eq(%w(project.clj deps.edn))
      end
    end

    context "without a manifest" do
      let(:repo_contents_path) { write_tmp_repo([Dependabot::DependencyFile.new(name: "README.md", content: "")]) }

      it "raises a helpful error" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound, /project.clj or a deps.edn/)
      end
    end

    context "when beta ecosystems are disabled" do
      before { allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false) }

      it "tells the user how to enable them" do
        expect { files }.to raise_error(Dependabot::DependencyFileNotFound, /enable-beta-ecosystems: true/)
      end
    end
  end
end
