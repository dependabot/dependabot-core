# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Bazel::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { github_url + "repos/example/repo/contents/" }
  let(:github_url) { "https://api.github.com/" }
  let(:directory) { "/" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_beta_ecosystems).and_return(true)
  end

  it_behaves_like "a dependency file fetcher"

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with a WORKSPACE file" do
      let(:filenames) { %w(WORKSPACE README.md) }

      it { is_expected.to be(true) }
    end

    context "with a WORKSPACE.bazel file" do
      let(:filenames) { %w(WORKSPACE.bazel README.md) }

      it { is_expected.to be(true) }
    end

    context "with a MODULE.bazel file" do
      let(:filenames) { %w(MODULE.bazel README.md) }

      it { is_expected.to be(true) }
    end

    context "without any Bazel files" do
      let(:filenames) { %w(README.md package.json) }

      it { is_expected.to be(false) }
    end
  end

  describe "#fetch_files" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    before do
      allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(true)
    end

    context "with a WORKSPACE file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_simple.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "WORKSPACE?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_workspace.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "BUILD?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_build.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the WORKSPACE and BUILD files" do
        expect(fetched_files.map(&:name)).to contain_exactly("WORKSPACE", "BUILD")
      end
    end

    context "with a MODULE.bazel file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_module.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the MODULE.bazel file" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end
    end

    context "when beta ecosystems are not allowed" do
      before do
        allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "raises a DependencyFileNotFound error with beta message" do
        expect { fetched_files }.to raise_error(
          Dependabot::DependencyFileNotFound,
          /Bazel is currently in beta/
        )
      end
    end

    context "without any required files" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_empty.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a DependencyFileNotFound error" do
        expect { fetched_files }.to raise_error(
          Dependabot::DependencyFileNotFound,
          /must contain a WORKSPACE, WORKSPACE.bazel, or MODULE.bazel file/
        )
      end
    end
  end

  describe "#ecosystem_versions" do
    subject(:ecosystem_versions) { file_fetcher_instance.ecosystem_versions }

    before do
      allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(true)
    end

    context "with a .bazelversion file" do
      before do
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(
            status: 200,
            body: fixtures("github", "contents_bazel_version.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "returns the Bazel version from .bazelversion" do
        expect(ecosystem_versions).to eq({ package_managers: { "bazel" => "6.0.0" } })
      end
    end

    context "without a .bazelversion file" do
      before do
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(status: 404)
      end

      it "returns unknown version" do
        expect(ecosystem_versions).to eq({ package_managers: { "bazel" => "unknown" } })
      end
    end
  end
end
