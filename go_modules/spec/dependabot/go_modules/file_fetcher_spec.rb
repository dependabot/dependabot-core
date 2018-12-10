# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GoModules::FileFetcher, :vcr do
  it_behaves_like "a dependency file fetcher"

  let(:repo) { "dependabot-fixtures/go-modules-lib" }
  let(:branch) { "master" }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: directory,
      branch: branch
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: github_credentials)
  end
  let(:directory) { "/" }

  it "fetches the go.mod and go.sum" do
    expect(file_fetcher_instance.files.map(&:name)).
      to include("go.mod", "go.sum")
  end

  context "without a go.mod" do
    let(:branch) { "without-go-mod" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "without a go.sum" do
    let(:branch) { "without-go-sum" }

    it "doesn't raise an error" do
      expect { file_fetcher_instance.files }.to_not raise_error
    end
  end

  context "for an application" do
    let(:repo) { "dependabot-fixtures/go-modules-app" }

    it "fetches the main.go, too" do
      expect(file_fetcher_instance.files.map(&:name)).
        to include("main.go")
      expect(file_fetcher_instance.files.
        find { |f| f.name == "main.go" }.type).to eq("package_main")
    end
  end
end
