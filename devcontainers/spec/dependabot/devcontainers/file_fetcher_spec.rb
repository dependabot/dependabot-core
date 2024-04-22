# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/devcontainers/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Devcontainers::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/devcontainers-example",
      directory: directory
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end

  let(:repo_contents_path) { build_tmp_repo(project_name) }

  context "with a lone .devcontainer.json in repo root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.devcontainer.json))
    end
  end

  context "with a .devcontainer folder" do
    let(:project_name) { "config_in_dot_devcontainer_folder" }
    let(:directory) { "/" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.devcontainer/devcontainer.json))
    end
  end

  context "with repo that has multiple, valid dev container configs" do
    let(:project_name) { "multiple_configs" }
    let(:directory) { "/" }
    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.devcontainer.json .devcontainer/devcontainer.json))
    end
  end

  context "with devcontainer.json files inside custom directories inside .devcontainer folder" do
    let(:project_name) { "custom_configs" }
    let(:directory) { "/" }

    it "fetches the correct files" do
      expect(file_fetcher_instance.files.map(&:name))
        .to match_array(%w(.devcontainer/foo/devcontainer.json .devcontainer/bar/devcontainer.json))
    end
  end

  context "with a directory that doesn't exist" do
    let(:project_name) { "multiple_configs" }
    let(:directory) { "/.devcontainer/nonexistent" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }
        .to raise_error(Dependabot::DependencyFileNotFound)
        .with_message(
          "Neither .devcontainer.json nor .devcontainer/devcontainer.json nor " \
          ".devcontainer/<anything>/devcontainer.json found in /.devcontainer/nonexistent"
        )
    end
  end
end
