# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Mise::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:directory) { "/" }
  let(:repo_contents_path) { nil }
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
      repo_contents_path: repo_contents_path
    )
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  it_behaves_like "a dependency file fetcher"

  describe ".mise_config_file?" do
    it "returns true for mise.toml" do
      expect(described_class.mise_config_file?("mise.toml")).to be(true)
    end

    it "returns true for .mise.toml" do
      expect(described_class.mise_config_file?(".mise.toml")).to be(true)
    end

    it "returns true for environment-specific variants" do
      expect(described_class.mise_config_file?("mise.production.toml")).to be(true)
      expect(described_class.mise_config_file?("mise.dev.toml")).to be(true)
      expect(described_class.mise_config_file?("mise.local.toml")).to be(true)
      expect(described_class.mise_config_file?("mise.staging.toml")).to be(true)
      expect(described_class.mise_config_file?("mise.test.toml")).to be(true)
    end

    it "returns true for dotfile environment-specific variants" do
      expect(described_class.mise_config_file?(".mise.production.toml")).to be(true)
      expect(described_class.mise_config_file?(".mise.dev.toml")).to be(true)
      expect(described_class.mise_config_file?(".mise.local.toml")).to be(true)
    end

    it "returns true for environment names with hyphens and underscores" do
      expect(described_class.mise_config_file?("mise.my-env.toml")).to be(true)
      expect(described_class.mise_config_file?("mise.my_env.toml")).to be(true)
      expect(described_class.mise_config_file?(".mise.test-env.toml")).to be(true)
    end

    it "returns true for environment-specific local overrides" do
      expect(described_class.mise_config_file?("mise.production.local.toml")).to be(true)
      expect(described_class.mise_config_file?(".mise.dev.local.toml")).to be(true)
    end

    it "returns true for the standard configuration directories" do
      %w(
        .config/mise.toml .config/mise.local.toml .config/mise.production.local.toml
        .config/mise/config.toml .config/mise/config.local.toml .config/mise/config.dev.local.toml
        .config/mise/mise.toml .config/mise/mise.local.toml
        .mise/config.toml .mise/config.production.toml .mise/config.production.local.toml
        mise/config.toml mise/config.local.toml mise/config.my-env.toml
      ).each do |filename|
        expect(described_class.mise_config_file?(filename)).to be(true), filename
      end
    end

    it "returns true for TOML fragments" do
      %w(.config/mise/conf.d/tools.toml .mise/conf.d/00-node.toml mise/conf.d/tools.dev.local.toml).each do |filename|
        expect(described_class.mise_config_file?(filename)).to be(true), filename
      end
    end

    it "returns true for mise files in conf.d folders" do
      %w(
        mise/conf.d/node/mise.toml .config/mise/conf.d/git/mise.local.toml
        .mise/conf.d/tools/mise.dev.toml mise/conf.d/tools/mise.dev.local.toml
      ).each do |filename|
        expect(described_class.mise_config_file?(filename)).to be(true), filename
      end
    end

    it "returns false for non-mise files" do
      expect(described_class.mise_config_file?("README.md")).to be(false)
      expect(described_class.mise_config_file?("package.json")).to be(false)
      expect(described_class.mise_config_file?("mise.txt")).to be(false)
    end

    it "returns false for files with invalid patterns" do
      expect(described_class.mise_config_file?("mise..toml")).to be(false)
      expect(described_class.mise_config_file?("mise.toml.bak")).to be(false)
      expect(described_class.mise_config_file?("my-mise.toml")).to be(false)
    end

    it "returns false for unrelated TOML files and unsupported locations" do
      %w(
        config.toml .config/config.toml .config/.mise.toml mise/settings.toml
        other/mise.toml .config/mise/mise.dev.toml .mise/conf.d/.hidden.toml
        mise/conf.d/node/config.toml mise/conf.d/node/tools.toml mise/conf.d/.hidden/mise.toml
        mise/conf.d/node/nested/mise.toml nginx/conf.d/site/mise.toml
        .rtx.toml .tool-versions .ruby-version
      ).each do |filename|
        expect(described_class.mise_config_file?(filename)).to be(false), filename
      end
    end
  end

  describe ".lockfile_path_for" do
    {
      "mise.toml" => "mise.lock",
      ".mise.toml" => "mise.lock",
      "mise.dev.toml" => "mise.dev.lock",
      ".mise.dev.toml" => "mise.dev.lock",
      "mise.local.toml" => "mise.local.lock",
      "mise.dev.local.toml" => "mise.dev.local.lock",
      ".config/mise.toml" => ".config/mise.lock",
      ".config/mise/config.toml" => ".config/mise/mise.lock",
      ".config/mise/config.dev.toml" => ".config/mise/mise.dev.lock",
      ".config/mise/mise.local.toml" => ".config/mise/mise.local.lock",
      ".mise/config.toml" => ".mise/mise.lock",
      "mise/config.local.toml" => "mise/mise.local.lock",
      "mise/conf.d/tools.toml" => "mise/mise.lock",
      ".config/mise/conf.d/tools.local.toml" => ".config/mise/mise.local.lock",
      "mise/conf.d/node/mise.toml" => "mise/mise.lock",
      ".mise/conf.d/node/mise.dev.toml" => ".mise/mise.dev.lock"
    }.each do |config, lockfile|
      it "maps #{config} to #{lockfile}" do
        expect(described_class.lockfile_path_for(config)).to eq(lockfile)
      end
    end
  end

  describe ".sidecar_dirs" do
    def lockfile(entries)
      entries.map { |line| "[[tools.\"npm:prettier\"]]\nversion = \"3.3.0\"\n#{line}\n" }.join
    end

    it "reads a root lockfile's paths from the repository root" do
      content = lockfile(["aube = { path = \".mise/locks/npm-prettier/3.3.0\", digest = \"sha256:abc\" }"])
      expect(described_class.sidecar_dirs("mise.lock", content)).to eq([".mise/locks/npm-prettier/3.3.0"])
    end

    it "reads a nested lockfile's paths from its own directory" do
      content = lockfile(["aube = { path = \"mise/locks/npm-prettier/3.3.0\", digest = \"sha256:abc\" }"])
      expect(described_class.sidecar_dirs(".config/mise.lock", content))
        .to eq([".config/mise/locks/npm-prettier/3.3.0"])
    end

    it "reads both sidecar kinds" do
      content = "[[tools.\"pipx:black\"]]\nversion = \"24.1.0\"\n" \
                "uv = { path = \"locks/pipx-black/24.1.0\", digest = \"sha256:abc\" }\n"
      expect(described_class.sidecar_dirs(".mise/mise.lock", content)).to eq([".mise/locks/pipx-black/24.1.0"])
    end

    it "ignores other tables, absolute paths and paths that leave the directory" do
      content = lockfile(
        [
          "options = { path = \"bin/tool\" }",
          "aube = { path = \"/etc/locks\", digest = \"sha256:abc\" }",
          "aube = { path = \"../../outside\", digest = \"sha256:abc\" }"
        ]
      )
      expect(described_class.sidecar_dirs("mise.lock", content)).to be_empty
    end
  end

  describe ".required_files_in?" do
    it "returns true when any mise config file is present" do
      filenames = ["README.md", "package.json", ".mise/config.dev.toml", "Gemfile"]
      expect(described_class.required_files_in?(filenames)).to be(true)
    end

    it "returns false when no mise config files are present" do
      expect(described_class.required_files_in?(["README.md", "package.json"])).to be(false)
    end
  end

  describe ".required_files_message" do
    it "returns a helpful message" do
      expect(described_class.required_files_message)
        .to eq(
          "Repo must contain a mise TOML configuration file " \
          "(for example, mise.toml or .config/mise/config.toml)."
        )
    end
  end

  describe "#fetch_files" do
    let(:repo_contents_path) { Dir.mktmpdir }
    let(:manifest_names) do
      %w(
        mise.toml mise.production.local.toml .mise.toml .mise.dev.local.toml
        .config/mise.toml .config/mise.dev.local.toml
        .config/mise/config.toml .config/mise/config.production.local.toml
        .config/mise/mise.toml .config/mise/mise.local.toml
        .mise/config.toml .mise/config.local.toml mise/config.toml mise/config.dev.toml
        .config/mise/conf.d/tools.toml .mise/conf.d/node.toml mise/conf.d/tools.dev.local.toml
        mise/conf.d/node/mise.toml mise/conf.d/node/mise.dev.local.toml .config/mise/conf.d/git/mise.local.toml
      )
    end
    let(:other_files) do
      %w(
        README.md .config/other.toml mise/settings.toml .mise/conf.d/.hidden.toml other/mise.toml .rtx.toml
        mise/conf.d/node/tools.toml mise/conf.d/.hidden/mise.toml mise/conf.d/node/nested/mise.toml
      )
    end

    before do
      Dependabot::Experiments.register(:enable_beta_ecosystems, true)
      allow(file_fetcher_instance).to receive(:clone_repo_contents).and_return(repo_contents_path)
      (manifest_names + other_files).each do |filename|
        path = File.join(repo_contents_path, directory, filename)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "[tools]\nnode = '20.0.0'\n")
      end
    end

    after { FileUtils.remove_entry(repo_contents_path) }

    it "fetches the supported manifests and preserves their relative paths" do
      expect(file_fetcher_instance.files.map(&:name)).to match_array(manifest_names)
    end

    context "with only a root manifest" do
      let(:manifest_names) { ["mise.toml"] }
      let(:other_files) { [] }

      it "allows the optional configuration directories to be absent" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(["mise.toml"])
      end
    end

    context "with lockfiles" do
      let(:manifest_names) { %w(mise.toml mise.dev.toml mise/conf.d/node.toml mise/conf.d/git/mise.toml) }
      let(:other_files) { %w(mise.lock mise/mise.lock mise.ci.lock .mise/mise.lock) }

      it "fetches the lockfiles that belong to a fetched manifest" do
        expect(file_fetcher_instance.files.map(&:name)).to match_array(manifest_names + %w(mise.lock mise/mise.lock))
      end

      context "when a lockfile references sidecar files" do
        let(:sidecar) { ".mise/locks/npm-prettier/3.3.0" }

        before do
          lock = "[[tools.\"npm:prettier\"]]\nversion = \"3.3.0\"\n" \
                 "aube = { path = \"#{sidecar}\", digest = \"sha256:abc\" }\n"
          File.write(File.join(repo_contents_path, "mise.lock"), lock)
          %W(#{sidecar}/package.json #{sidecar}/nested/aube-lock.yaml .mise/locks/npm-other/1.0.0/package.json)
            .each do |path|
            FileUtils.mkdir_p(File.join(repo_contents_path, File.dirname(path)))
            File.write(File.join(repo_contents_path, path), "{}")
          end
        end

        it "fetches the referenced sidecar files only" do
          expect(file_fetcher_instance.files.map(&:name)).to match_array(
            manifest_names + %W(mise.lock mise/mise.lock #{sidecar}/package.json #{sidecar}/nested/aube-lock.yaml)
          )
        end
      end

      it "still requires a manifest" do
        expect(described_class.required_files_in?(%w(mise.lock))).to be(false)
      end
    end

    context "when two lockfiles share a sidecar directory" do
      let(:manifest_names) { %w(mise.toml .mise/config.toml) }
      let(:other_files) { %w(mise.lock .mise/mise.lock .mise/locks/npm-prettier/3.3.0/package.json) }

      before do
        { "mise.lock" => ".mise/locks/npm-prettier/3.3.0", ".mise/mise.lock" => "locks/npm-prettier/3.3.0" }
          .each do |lockfile, recorded|
          File.write(
            File.join(repo_contents_path, lockfile),
            "[[tools.\"npm:prettier\"]]\nversion = \"3.3.0\"\n" \
            "aube = { path = \"#{recorded}\", digest = \"sha256:abc\" }\n"
          )
        end
      end

      it "fetches the shared sidecar files once" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(file_fetcher_instance.files.map(&:name).uniq)
        expect(file_fetcher_instance.files.map(&:name)).to match_array(manifest_names + other_files)
      end
    end

    context "with a configured subdirectory" do
      let(:directory) { "/project" }

      it "fetches manifests relative to that directory" do
        expect(file_fetcher_instance.files.map { |file| [file.name, file.directory] })
          .to match_array(manifest_names.map { |name| [name, "/project"] })
      end
    end

    context "without any supported manifests" do
      let(:manifest_names) { [] }

      it "raises a helpful error" do
        expect { file_fetcher_instance.files }
          .to raise_error(Dependabot::DependencyFileNotFound, described_class.required_files_message)
      end
    end
  end
end
