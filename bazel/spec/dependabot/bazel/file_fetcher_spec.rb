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

  describe "#extract_referenced_paths" do
    let(:module_content) do
      <<~BAZEL
        bazel_dep(name = "rules_python", version = "1.6.3")

        pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
        pip.parse(
            hub_name = "pip",
            requirements_lock = "//python:requirements.txt",
        )

        maven = use_extension("@rules_jvm_external//extension:maven.bzl", "maven")
        maven.install(
            lock_file = "@batfish//:maven_install.json",
            name = "maven",
        )

        maven.install(
            lock_file = "//tools/jol:jol_maven_install.json",
            name = "jmh_maven",
        )
      BAZEL
    end

    let(:module_file) do
      Dependabot::DependencyFile.new(
        name: "MODULE.bazel",
        content: module_content
      )
    end

    it "extracts paths from lock_file attributes with @repo prefix" do
      paths = file_fetcher_instance.send(:extract_referenced_paths, module_file)
      expect(paths).to include("maven_install.json")
    end

    it "extracts paths from lock_file attributes without @repo prefix" do
      paths = file_fetcher_instance.send(:extract_referenced_paths, module_file)
      expect(paths).to include("tools/jol/jol_maven_install.json")
    end

    it "extracts paths from requirements_lock attributes" do
      paths = file_fetcher_instance.send(:extract_referenced_paths, module_file)
      expect(paths).to include("python/requirements.txt")
    end

    it "converts Bazel label colons to forward slashes" do
      paths = file_fetcher_instance.send(:extract_referenced_paths, module_file)
      expect(paths).to include("tools/jol/jol_maven_install.json")
      expect(paths).not_to include("tools/jol:jol_maven_install.json")
    end

    it "removes leading slashes from extracted paths" do
      paths = file_fetcher_instance.send(:extract_referenced_paths, module_file)
      paths.each do |path|
        expect(path).not_to start_with("/")
      end
    end

    it "returns unique paths when same file is referenced multiple times" do
      duplicate_content = module_content + "\nmaven.install(lock_file = \"//tools/jol:jol_maven_install.json\")\n"
      duplicate_file = Dependabot::DependencyFile.new(
        name: "MODULE.bazel",
        content: duplicate_content
      )
      paths = file_fetcher_instance.send(:extract_referenced_paths, duplicate_file)
      expect(paths.count("tools/jol/jol_maven_install.json")).to eq(1)
    end

    it "handles empty content gracefully" do
      empty_file = Dependabot::DependencyFile.new(
        name: "MODULE.bazel",
        content: ""
      )
      paths = file_fetcher_instance.send(:extract_referenced_paths, empty_file)
      expect(paths).to eq([])
    end

    it "handles content with no references gracefully" do
      simple_file = Dependabot::DependencyFile.new(
        name: "MODULE.bazel",
        content: 'bazel_dep(name = "rules_python", version = "1.6.3")'
      )
      paths = file_fetcher_instance.send(:extract_referenced_paths, simple_file)
      expect(paths).to eq([])
    end

    it "extracts patch files from single_version_override" do
      content_with_patches = <<~BAZEL
        single_version_override(
            module_name = "googleapis",
            patch_strip = 1,
            patches = ["//third_party:googleapis.patch"],
            version = "0.0.0-20250604-de157ca3",
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_patches)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).to include("third_party/googleapis.patch")
    end

    it "extracts multiple patch files from patches array" do
      content_with_patches = <<~BAZEL
        archive_override(
            module_name = "example",
            patches = [
                "//patches:fix1.patch",
                "//patches:fix2.patch",
                "//third_party:custom.patch",
            ],
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_patches)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).to include("patches/fix1.patch", "patches/fix2.patch", "third_party/custom.patch")
    end

    it "extracts local_path_override paths" do
      content_with_path = <<~BAZEL
        local_path_override(
            module_name = "remoteapis",
            path = "third_party/remoteapis",
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_path)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).to include("third_party/remoteapis")
    end

    it "extracts relative path overrides with dot notation" do
      content_with_path = <<~BAZEL
        local_path_override(
            module_name = "local_module",
            path = "./third_party/local",
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_path)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).to include("./third_party/local")
    end

    it "does not extract absolute paths" do
      content_with_absolute = <<~BAZEL
        local_path_override(
            module_name = "system_module",
            path = "/usr/local/lib/module",
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_absolute)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).not_to include("/usr/local/lib/module")
    end

    it "does not extract URL paths" do
      content_with_url = <<~BAZEL
        local_path_override(
            module_name = "remote_module",
            path = "https://example.com/module",
        )
      BAZEL
      file = Dependabot::DependencyFile.new(name: "MODULE.bazel", content: content_with_url)
      paths = file_fetcher_instance.send(:extract_referenced_paths, file)
      expect(paths).not_to include("https://example.com/module")
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

  describe "#extract_downloader_config_paths" do
    let(:bazelrc_content_with_equals) do
      <<~BAZELRC
        # Bazel configuration file
        build --java_runtime_version=remotejdk_11

        # Custom downloader configuration for mirrors
        build --downloader_config=downloader.cfg

        # Other build options
        test --test_output=all
      BAZELRC
    end

    let(:bazelrc_content_with_space) do
      <<~BAZELRC
        build --downloader_config downloader.cfg
        test --downloader_config secondary.cfg
      BAZELRC
    end

    let(:bazelrc_content_multiple) do
      <<~BAZELRC
        build --downloader_config=primary.cfg
        test --downloader_config secondary.cfg
        run --downloader_config=mirrors/custom.cfg
      BAZELRC
    end

    let(:bazelrc_content_no_config) do
      <<~BAZELRC
        build --java_runtime_version=remotejdk_11
        test --test_output=all
      BAZELRC
    end

    it "extracts downloader_config path with equals syntax" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: bazelrc_content_with_equals
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to eq(["downloader.cfg"])
    end

    it "extracts downloader_config path with space syntax" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: bazelrc_content_with_space
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to contain_exactly("downloader.cfg", "secondary.cfg")
    end

    it "extracts multiple downloader_config paths" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: bazelrc_content_multiple
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to contain_exactly("primary.cfg", "secondary.cfg", "mirrors/custom.cfg")
    end

    it "handles paths in subdirectories" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: bazelrc_content_multiple
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to include("mirrors/custom.cfg")
    end

    it "returns empty array when no downloader_config is present" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: bazelrc_content_no_config
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to eq([])
    end

    it "handles empty content gracefully" do
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: ""
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths).to eq([])
    end

    it "returns unique paths when same config is referenced multiple times" do
      duplicate_content = bazelrc_content_with_equals + "\ntest --downloader_config=downloader.cfg\n"
      bazelrc_file = Dependabot::DependencyFile.new(
        name: ".bazelrc",
        content: duplicate_content
      )
      paths = file_fetcher_instance.send(:extract_downloader_config_paths, bazelrc_file)
      expect(paths.count("downloader.cfg")).to eq(1)
    end
  end
end
