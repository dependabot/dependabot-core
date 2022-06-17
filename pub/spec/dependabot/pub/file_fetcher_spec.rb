# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Pub::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end

  let(:project_name) { "pinned_version" }
  let(:directory) { "/" }
  let(:repo_contents_path) { build_tmp_repo(project_name) }

  after do
    FileUtils.rm_rf(repo_contents_path)
  end

  context "with pubspec.yaml and pubspec.lock" do
    it "fetches the  files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(pubspec.yaml pubspec.lock))
    end
  end

  context "mono-repo" do
    let(:project_name) { "mono_repo" }
    let(:directory) { "/main" }
    it "fetches the  files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(pubspec.yaml pubspec.lock ../dep/pubspec.yaml))
    end
  end

  context "mono-repo, no pubspec.lock" do
    let(:project_name) { "no_lockfile" }
    let(:directory) { "/main" }
    it "fetches the  files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(pubspec.yaml ../dep/pubspec.yaml))
    end
  end
end
