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
        # BUILD file is listed in contents_bazel_simple.json, so we need to stub its content
        stub_request(:get, url + "BUILD?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_build.json"),
            headers: { "content-type" => "application/json" }
          )

        # Stub optional config files that may be fetched
        stub_request(:get, url + ".bazelrc?ref=sha").to_return(status: 404)
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha").to_return(status: 404)
      end

      it "fetches the WORKSPACE file" do
        expect(fetched_files.map(&:name)).to contain_exactly("WORKSPACE", "BUILD")
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

  describe "#referenced_files_from_modules" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    context "with MODULE.bazel containing lock_file and requirements_lock references" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_references.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_with_references.json"),
            headers: { "content-type" => "application/json" }
          )

        # Mock referenced files
        stub_request(:get, url + "maven_install.json?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_maven_install.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "python/requirements.txt?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_python_requirements.json"),
            headers: { "content-type" => "application/json" }
          )

        # Stub directory listings (needed for fetch_file_if_present to check if files exist)
        stub_request(:get, url + "python?ref=sha")
          .to_return(
            status: 200,
            body: '[{"name": "requirements.txt", "type": "file"}, {"name": "BUILD.bazel", "type": "file"}]',
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/jol?ref=sha")
          .to_return(
            status: 200,
            body: '[{"name": "jol_maven_install.json", "type": "file"}, {"name": "BUILD.bazel", "type": "file"}]',
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/benchmarks?ref=sha")
          .to_return(
            status: 200,
            body: '[{"name": "jmh_maven_install.json", "type": "file"}]',
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/jol/jol_maven_install.json?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_jol_maven_install.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/benchmarks/jmh_maven_install.json?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_maven_install.json"),
            headers: { "content-type" => "application/json" }
          )

        # Mock BUILD files for directories
        stub_request(:get, url + "BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "BUILD.bazel?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "python/BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "python/BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_python_build.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/jol/BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "tools/jol/BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_tools_jol_build.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "tools/benchmarks/BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "tools/benchmarks/BUILD.bazel?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(status: 404)

        # Stub optional config files
        stub_request(:get, url + ".bazelrc?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "MODULE.bazel.lock?ref=sha")
          .to_return(status: 404)
      end

      it "fetches lock files referenced in lock_file attributes" do
        expect(fetched_files.map(&:name)).to include(
          "maven_install.json",
          "tools/jol/jol_maven_install.json",
          "tools/benchmarks/jmh_maven_install.json"
        )
      end

      it "fetches requirements files referenced in requirements_lock attributes" do
        expect(fetched_files.map(&:name)).to include("python/requirements.txt")
      end

      it "fetches BUILD.bazel files from directories containing referenced files" do
        expect(fetched_files.map(&:name)).to include(
          "python/BUILD.bazel",
          "tools/jol/BUILD.bazel"
        )
      end

      it "does not fail when BUILD files are missing from some directories" do
        expect(fetched_files.map(&:name)).not_to include("tools/benchmarks/BUILD.bazel")
        expect(fetched_files.map(&:name)).to include("tools/benchmarks/jmh_maven_install.json")
      end

      it "handles @repo//path:file format correctly" do
        maven_file = fetched_files.find { |f| f.name == "maven_install.json" }
        expect(maven_file).not_to be_nil
      end

      it "handles //path:file format correctly" do
        python_file = fetched_files.find { |f| f.name == "python/requirements.txt" }
        expect(python_file).not_to be_nil
      end

      it "fetches all files needed for bazel mod tidy to succeed" do
        expected_files = [
          "MODULE.bazel",
          "maven_install.json",
          "python/requirements.txt",
          "python/BUILD.bazel",
          "tools/jol/jol_maven_install.json",
          "tools/jol/BUILD.bazel",
          "tools/benchmarks/jmh_maven_install.json"
        ]
        expect(fetched_files.map(&:name)).to include(*expected_files)
      end
    end

    context "when MODULE.bazel has no file references" do
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

        stub_request(:get, url + ".bazelversion?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "BUILD.bazel?ref=sha")
          .to_return(status: 404)

        # Stub optional config files
        stub_request(:get, url + ".bazelrc?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "MODULE.bazel.lock?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "maven_install.json?ref=sha")
          .to_return(status: 404)
      end

      it "does not attempt to fetch referenced files" do
        expect(fetched_files.map(&:name)).to eq(["MODULE.bazel"])
      end
    end
  end

  describe "fetching local_path_override directories" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    context "with MODULE.bazel containing local_path_override" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        # Mock the local_path_override directory listing
        stub_request(:get, url + "third_party/remoteapis?ref=sha")
          .to_return(
            status: 200,
            body: '[{"name": "MODULE.bazel", "path": "third_party/remoteapis/MODULE.bazel", "type": "file"}, ' \
                  '{"name": "BUILD.bazel", "path": "third_party/remoteapis/BUILD.bazel", "type": "file"}]',
            headers: { "content-type" => "application/json" }
          )

        # Mock the local_path_override directory files
        stub_request(:get, url + "third_party/remoteapis/MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_remoteapis_module.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "third_party/remoteapis/BUILD?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "third_party/remoteapis/BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_remoteapis_build.json"),
            headers: { "content-type" => "application/json" }
          )

        # Stub other optional config files
        stub_request(:get, url + ".bazelrc?ref=sha").to_return(status: 404)
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_root_build.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches MODULE.bazel from the local_path_override directory" do
        expect(fetched_files.map(&:name)).to include("third_party/remoteapis/MODULE.bazel")
      end

      it "fetches BUILD.bazel from the local_path_override directory" do
        expect(fetched_files.map(&:name)).to include("third_party/remoteapis/BUILD.bazel")
      end

      it "includes the main MODULE.bazel file" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end
    end

    context "when local_path_override directory uses WORKSPACE instead of MODULE.bazel" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        # Mock the local_path_override directory listing
        stub_request(:get, url + "third_party/remoteapis?ref=sha")
          .to_return(
            status: 200,
            body: '[{"name": "WORKSPACE", "path": "third_party/remoteapis/WORKSPACE", "type": "file"}, ' \
                  '{"name": "BUILD", "path": "third_party/remoteapis/BUILD", "type": "file"}]',
            headers: { "content-type" => "application/json" }
          )

        # This local override directory has WORKSPACE instead of MODULE.bazel
        stub_request(:get, url + "third_party/remoteapis/MODULE.bazel?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "third_party/remoteapis/WORKSPACE.bazel?ref=sha")
          .to_return(status: 404)

        stub_request(:get, url + "third_party/remoteapis/WORKSPACE?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_remoteapis_workspace.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "third_party/remoteapis/BUILD?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_remoteapis_build.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "third_party/remoteapis/BUILD.bazel?ref=sha")
          .to_return(status: 404)

        # Stub other optional config files
        stub_request(:get, url + ".bazelrc?ref=sha").to_return(status: 404)
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_root_build.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches WORKSPACE from the local_path_override directory" do
        expect(fetched_files.map(&:name)).to include("third_party/remoteapis/WORKSPACE")
      end

      it "fetches BUILD from the local_path_override directory" do
        expect(fetched_files.map(&:name)).to include("third_party/remoteapis/BUILD")
      end
    end

    context "when local_path_override directory is inaccessible" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_with_local_override.json"),
            headers: { "content-type" => "application/json" }
          )

        # Mock the local_path_override directory as not found
        stub_request(:get, url + "third_party/remoteapis?ref=sha")
          .to_return(status: 404)

        # Stub other optional config files
        stub_request(:get, url + ".bazelrc?ref=sha").to_return(status: 404)
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_root_build.json"),
            headers: { "content-type" => "application/json" }
          )

        allow(Dependabot.logger).to receive(:warn)
      end

      it "logs a warning about the inaccessible directory" do
        fetched_files
        expect(Dependabot.logger).to have_received(:warn).with(
          %r{Skipping inaccessible directory 'third_party/remoteapis'}
        )
      end

      it "continues fetching other files" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel")
      end
    end
  end

  describe "fetching downloader_config files" do
    subject(:fetched_files) { file_fetcher_instance.fetch_files }

    context "with a .bazelrc file containing downloader_config" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_downloader_config.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".bazelrc?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_bazelrc_with_downloader.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "downloader.cfg?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_downloader_config.json"),
            headers: { "content-type" => "application/json" }
          )

        # Stub other optional config files
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha").to_return(status: 404)
      end

      it "fetches the downloader config file" do
        expect(fetched_files.map(&:name)).to include("downloader.cfg")
      end

      it "includes MODULE.bazel and .bazelrc" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel", ".bazelrc")
      end
    end

    context "when downloader_config file is missing" do
      before do
        stub_request(:get, url + "?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_with_downloader_config.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "MODULE.bazel?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_module_file.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + ".bazelrc?ref=sha")
          .to_return(
            status: 200,
            body: fixture("github", "contents_bazel_bazelrc_with_downloader.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "downloader.cfg?ref=sha")
          .to_return(status: 404)

        # Stub other optional config files
        stub_request(:get, url + "MODULE.bazel.lock?ref=sha").to_return(status: 404)
        stub_request(:get, url + ".bazelversion?ref=sha").to_return(status: 404)
        stub_request(:get, url + "maven_install.json?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD?ref=sha").to_return(status: 404)
        stub_request(:get, url + "BUILD.bazel?ref=sha").to_return(status: 404)
      end

      it "logs a warning when downloader config file is not found" do
        allow(Dependabot.logger).to receive(:warn)
        fetched_files
        expect(Dependabot.logger).to have_received(:warn).with(
          "Downloader config file 'downloader.cfg' referenced in .bazelrc but not found in repository"
        )
      end

      it "continues fetching other files successfully" do
        expect(fetched_files.map(&:name)).to include("MODULE.bazel", ".bazelrc")
        expect(fetched_files.map(&:name)).not_to include("downloader.cfg")
      end
    end

    context "when .bazelrc is not present" do
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
        stub_request(:get, url + ".bazelrc?ref=sha").to_return(status: 404)
      end

      it "does not attempt to fetch downloader config files" do
        expect(fetched_files.map(&:name)).not_to include("downloader.cfg")
      end
    end
  end
end
