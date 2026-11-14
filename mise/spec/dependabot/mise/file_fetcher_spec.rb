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
  let(:url) { github_url + "repos/example/repo/contents/" }
  let(:github_url) { "https://api.github.com/" }
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

  describe ".required_files_in?" do
    it "returns true when mise.toml is present" do
      expect(described_class.required_files_in?(["mise.toml"])).to be(true)
    end

    it "returns true when .mise.toml is present" do
      expect(described_class.required_files_in?([".mise.toml"])).to be(true)
    end

    it "returns true when environment-specific variant is present" do
      expect(described_class.required_files_in?(["mise.production.toml"])).to be(true)
      expect(described_class.required_files_in?([".mise.local.toml"])).to be(true)
    end

    it "returns true when only a nested configuration file is present" do
      expect(described_class.required_files_in?([".mise/config.toml"])).to be(true)
      expect(described_class.required_files_in?(["mise/conf.d/tools.toml"])).to be(true)
    end

    it "returns true when any mise config file is present" do
      filenames = ["README.md", "package.json", "mise.dev.toml", "Gemfile"]
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
          .to raise_error(Dependabot::DependencyFileNotFound, "No mise configuration file found")
      end
    end
  end
end
