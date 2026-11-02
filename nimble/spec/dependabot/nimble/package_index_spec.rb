# typed: false
# frozen_string_literal: true

require "json"

require "spec_helper"
require "dependabot/nimble/package_index"

RSpec.describe Dependabot::Nimble::PackageIndex do
  subject(:index) { described_class.new }

  let(:entries) do
    [
      { "name" => "chronos", "url" => "https://github.com/status-im/nim-chronos", "method" => "git" },
      { "name" => "Some_Pkg", "url" => "git://github.com/someone/some.git", "method" => "git" },
      { "name" => "oldname", "alias" => "chronos" },
      { "name" => "loop_a", "alias" => "loop_b" },
      { "name" => "loop_b", "alias" => "loop_a" },
      { "name" => "mercurial", "url" => "https://example.test/hg/repo", "method" => "hg" }
    ]
  end
  let(:status) { 200 }
  let(:body) { JSON.generate(entries) }

  let(:primary) { described_class::URLS.first }
  let(:fallback) { described_class::URLS.last }

  before do
    stub_request(:get, primary).to_return(status: status, body: body)
    stub_request(:get, fallback).to_return(status: 503, body: "unavailable")
  end

  it "finds the repository of a package" do
    expect(index.repository_url("chronos")).to eq("https://github.com/status-im/nim-chronos")
  end

  it "ignores case and underscores in names" do
    expect(index.repository_url("somepkg")).to eq("https://github.com/someone/some")
    expect(index.repository_url("SOME_pkg")).to eq("https://github.com/someone/some")
  end

  it "follows an alias" do
    expect(index.repository_url("oldname")).to eq("https://github.com/status-im/nim-chronos")
  end

  it "gives up on aliases that point at each other" do
    expect(index.repository_url("loop_a")).to be_nil
  end

  it "has no git repository for a package hosted with mercurial" do
    expect(index.repository_url("mercurial")).to be_nil
  end

  it "does not know an unlisted package" do
    expect(index.repository_url("nonesuch")).to be_nil
  end

  it "reads the index once" do
    index.repository_url("chronos")
    index.repository_url("somepkg")
    expect(WebMock).to have_requested(:get, primary).once
  end

  context "when the index cannot be fetched" do
    let(:status) { 503 }
    let(:body) { "unavailable" }

    it "knows no package" do
      expect(index.repository_url("chronos")).to be_nil
    end
  end

  context "when only the second address answers" do
    let(:status) { 404 }
    let(:body) { "not found" }

    before { stub_request(:get, fallback).to_return(status: 200, body: JSON.generate(entries)) }

    it "reads the index from there" do
      expect(index.repository_url("chronos")).to eq("https://github.com/status-im/nim-chronos")
    end
  end

  context "when the index is not JSON" do
    let(:body) { "<html>" }

    it "knows no package" do
      expect(index.repository_url("chronos")).to be_nil
    end
  end
end
