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

    it "returns false for directory paths" do
      expect(described_class.mise_config_file?(".config/mise.toml")).to be(false)
      expect(described_class.mise_config_file?(".mise/config.toml")).to be(false)
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
          "Repo must contain a mise configuration file " \
          "(mise.toml, .mise.toml, mise.<env>.toml, or .mise.<env>.toml)."
        )
    end
  end
end
