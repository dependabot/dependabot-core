# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/paket/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Paket::FileFetcher do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with only a paket.dependencies" do
      let(:filenames) { %w(paket.dependencies) }
      it { is_expected.to eq(false) }
    end
    context "with only a paket.lock" do
      let(:filenames) { %w(paket.lock) }
      it { is_expected.to eq(false) }
    end
    context "with both a paket.dependencies and paket.lock" do
      let(:filenames) { %w(paket.lock paket.dependencies) }
      it { is_expected.to eq(true) }
    end
  end

end
