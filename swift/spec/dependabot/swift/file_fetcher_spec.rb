# frozen_string_literal: true

require "spec_helper"
require "dependabot/swift/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Swift::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/swift-example",
      directory: directory
    )
  end

  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: [], repo_contents_path: repo_contents_path)
  end

  let(:repo_contents_path) { build_tmp_repo(project_name) }

  context "with Package.swift and Package.resolved" do
    let(:project_name) { "standard" }
    let(:directory) { "/" }

    it "fetches the manifest and resolved files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Package.swift Package.resolved))
    end
  end

  context "with Package.swift and Package.resolved" do
    let(:project_name) { "manifest-only" }
    let(:directory) { "/" }

    it "fetches the manifest and resolved files" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Package.swift))
    end
  end

  context "with a directory that doesn't exist" do
    let(:project_name) { "standard" }
    let(:directory) { "/nonexistent" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
