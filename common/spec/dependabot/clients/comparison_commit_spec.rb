# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/azure"
require "dependabot/clients/bitbucket"
require "dependabot/source"

RSpec.describe Dependabot::Clients::ComparisonCommit do
  describe Dependabot::Clients::Bitbucket do
    extend T::Sig

    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(Dependabot::Clients::Bitbucket) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
    let(:client) { described_class.new(credentials: nil) }

    sig { returns(String) }
    let(:url) { "https://api.bitbucket.org/2.0/repositories/test/repo/commits/?include=new&exclude=old" }

    sig { returns(String) }
    let(:response) do
      {
        "values" => %w(first second).map do |sha|
          {
            "hash" => sha,
            "summary" => { "raw" => "#{sha} message" },
            "links" => { "html" => { "href" => "https://example.com/#{sha}" } },
            "unused" => false
          }
        end
      }.to_json
    end
    # rubocop:enable RSpec/ScatteredLet

    before { stub_request(:get, url).to_return(status: 200, body: response) }

    it "returns decoded commits in response order" do
      commits = client.compare("test/repo", "old", "new")

      expect(commits.map { |commit| [commit.sha, commit.message, commit.html_url] }).to eq(
        [
          ["first", "first message", "https://example.com/first"],
          ["second", "second message", "https://example.com/second"]
        ]
      )
    end

    context "with no comparison commits" do
      sig { returns(String) }
      let(:response) { '{"values":[]}' }

      it "returns an empty result" do
        expect(client.compare("test/repo", "old", "new")).to eq([])
      end
    end

    context "with malformed nested commit fields" do
      sig { returns(String) }
      let(:response) { '{"values":[{"hash":"first","summary":{"raw":false},"links":{"html":{"href":"url"}}}]}' }

      it "reports the provider and operation" do
        expect { client.compare("test/repo", "old", "new") }
          .to raise_error(Dependabot::PrivateSourceBadResponse, /Malformed Bitbucket response for commit comparison/)
      end
    end
  end

  describe Dependabot::Clients::Azure do
    extend T::Sig

    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(Dependabot::Clients::Azure) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
    let(:client) { described_class.new(source, nil) }

    sig { returns(Dependabot::Source) }
    let(:source) { T.must(Dependabot::Source.from_url("https://dev.azure.com/org/project/_git/repo")) }

    sig { returns(String) }
    let(:url) do
      "https://dev.azure.com/org/project/_apis/git/repositories/repo/commits" \
        "?searchCriteria.itemVersion.versionType=tag&searchCriteria.itemVersion.version=old" \
        "&searchCriteria.compareVersion.versionType=tag&searchCriteria.compareVersion.version=new"
    end

    sig { returns(String) }
    let(:response) do
      {
        "value" => %w(first second).map do |sha|
          {
            "commitId" => sha,
            "comment" => "#{sha} message",
            "remoteUrl" => "https://example.com/#{sha}",
            "unused" => false
          }
        end
      }.to_json
    end
    # rubocop:enable RSpec/ScatteredLet

    before { stub_request(:get, url).to_return(status: 200, body: response) }

    it "returns decoded commits in response order" do
      commits = client.compare("old", "new", "tag")

      expect(commits.map { |commit| [commit.sha, commit.message, commit.html_url] }).to eq(
        [
          ["first", "first message", "https://example.com/first"],
          ["second", "second message", "https://example.com/second"]
        ]
      )
    end

    context "with no comparison commits" do
      sig { returns(String) }
      let(:response) { '{"value":[]}' }

      it "returns an empty result" do
        expect(client.compare("old", "new", "tag")).to eq([])
      end
    end

    context "with malformed commit fields" do
      sig { returns(String) }
      let(:response) { '{"value":[{"commitId":"first","comment":false,"remoteUrl":"url"}]}' }

      it "reports the provider and operation" do
        expect { client.compare("old", "new", "tag") }
          .to raise_error(Dependabot::PrivateSourceBadResponse, /Malformed Azure commit response/)
      end
    end
  end
end
