# frozen_string_literal: true

require "spec_helper"
require "dependabot/puppet/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Puppet::FileFetcher, :vcr do
  it_behaves_like "a dependency file fetcher"

  let(:repo) { "jpogran/control-repo" }
  let(:branch) { "production" }
  let(:directory) { "/" }
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

  it "fetches the Puppetfile" do
    expect(file_fetcher_instance.files.map(&:name)).
      to include("Puppetfile")
  end

  context "without a Puppetfile" do
    let(:branch) { "without-puppetfile" }

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end
end
