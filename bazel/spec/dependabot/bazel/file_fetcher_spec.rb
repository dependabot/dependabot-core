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
    allow(file_fetcher_instance).to receive_messages(commit: "sha", allow_beta_ecosystems?: true)
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

    context "with a *.MODULE.bazel file" do
      let(:filenames) { %w(deps.MODULE.bazel README.md) }

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
            body: fixture("github", "contents_bazel_simple.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "WORKSPACE?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_workspace.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the WORKSPACE file" do
        expect(fetched_files.map(&:name)).to contain_exactly("WORKSPACE")
      end
    end

    context "with a MODULE.bazel file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the MODULE.bazel file" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end

      context "with a maven_install.json file" do
        before do
          stub_request(:get, url + "?ref=sha")
            .to_return(
              status: 200,
              body: fixture("github", "contents_bazel_with_maven_install.json"),
              headers: { "content-type" => "application/json" }
            )

          stub_request(:get, url + "maven_install.json?ref=sha")
            .to_return(
              status: 200,
              body: fixture("github", "contents_bazel_maven_install.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "includes maven_install.json" do
          expect(fetched_files.map(&:name)).to include("maven_install.json")
        end
      end
    end

    context "with MODULE.bazel and *.MODULE.bazel files" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_additional_module.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "deps.MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_deps_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches all MODULE.bazel files including *.MODULE.bazel files" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel", "deps.MODULE.bazel")
      end
    end

    context "when beta ecosystems are not allowed" do
      before do
        allow(file_fetcher_instance).to receive(:allow_beta_ecosystems?).and_return(false)
      end

      it "raises a DependencyFileNotFound error with beta message" do
        expect { fetched_files }.to raise_error(
          Dependabot::DependencyFileNotFound,
          "Bazel support is currently in beta. To enable it, add `enable_beta_ecosystems: true` to the top-level of " \
          "your `dependabot.yml`. See https://docs.github.com/en/code-security/dependabot/working-with-dependabot/" \
          "dependabot-options-reference#enable-beta-ecosystems for details."
        )
      end
    end

    context "without any required files" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_empty.json"),
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

  describe "fetching .bazelversion from parent directories" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    context "when working in a subdirectory and .bazelversion is in parent" do
      let(:directory) { "/services" }

      before do
        # Subdirectory contents (no .bazelversion)
        stub_request(:get, url + "services?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => "MODULE.bazel",
                  "path" => "services/MODULE.bazel",
                  "type" => "file",
                  "sha" => "abc123"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "services/MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )

        # No .bazelversion in subdirectory
        stub_request(:get, url + "services/.bazelversion?ref=sha")
          .to_return(status: 404)

        # Parent directory contents listing (needed for file_fetcher to check parent)
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => ".bazelversion",
                  "path" => ".bazelversion",
                  "type" => "file"
                },
                {
                  "name" => "services",
                  "path" => "services",
                  "type" => "dir"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )

        # .bazelversion exists in parent directory
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_version.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches .bazelversion from parent directory" do
        expect(fetched_files.map(&:name)).to include(".bazelversion")
        bazelversion_file = fetched_files.find { |f| f.name == ".bazelversion" }
        expect(bazelversion_file).not_to be_nil
        expect(bazelversion_file.content).to eq("6.0.0\n")
      end

      it "includes MODULE.bazel from subdirectory" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end
    end

    context "when .bazelversion exists in current subdirectory" do
      let(:directory) { "/workspace" }

      before do
        stub_request(:get, url + "workspace?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => "MODULE.bazel",
                  "path" => "workspace/MODULE.bazel",
                  "type" => "file",
                  "sha" => "abc123"
                },
                {
                  "name" => ".bazelversion",
                  "path" => "workspace/.bazelversion",
                  "type" => "file",
                  "sha" => "def456"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "workspace/MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "workspace/.bazelversion?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_version_7.json"),
            headers: { "content-type" => "application/json" }
          )

        # Root directory also has .bazelversion but should be ignored
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => ".bazelversion",
                  "path" => ".bazelversion",
                  "type" => "file"
                },
                {
                  "name" => "workspace",
                  "path" => "workspace",
                  "type" => "dir"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )
      end

      it "uses .bazelversion from current directory (not parent)" do
        expect(fetched_files.map(&:name)).to include(".bazelversion")
        bazelversion_file = fetched_files.find { |f| f.name == ".bazelversion" }
        expect(bazelversion_file.content).to eq("7.0.0\n")
      end
    end

    context "when .bazelversion does not exist anywhere" do
      let(:directory) { "/apps" }

      before do
        stub_request(:get, url + "apps?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => "MODULE.bazel",
                  "path" => "apps/MODULE.bazel",
                  "type" => "file",
                  "sha" => "abc123"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "apps/MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )

        # Parent directory contents listing (no .bazelversion)
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: JSON.generate(
              [
                {
                  "name" => "apps",
                  "path" => "apps",
                  "type" => "dir"
                }
              ]
            ),
            headers: { "content-type" => "application/json" }
          )

        # No .bazelversion anywhere
        stub_request(:get, url + "apps/.bazelversion?ref=sha")
          .to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(status: 404)
      end

      it "does not include .bazelversion in fetched files" do
        expect(fetched_files.map(&:name)).not_to include(".bazelversion")
      end

      it "still fetches MODULE.bazel successfully" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end
    end
  end

  describe "#ecosystem_versions" do
    subject(:ecosystem_versions) { file_fetcher_instance.ecosystem_versions }

    context "with a .bazelversion file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_version.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_version.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "returns the Bazel version from .bazelversion" do
        expect(ecosystem_versions).to eq({ package_managers: { "bazel" => "6.0.0" } })
      end
    end

    context "without a .bazelversion file" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_simple.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(status: 404)
      end

      it "returns unknown version" do
        expect(ecosystem_versions).to eq({ package_managers: { "bazel" => "unknown" } })
      end
    end
  end
end
