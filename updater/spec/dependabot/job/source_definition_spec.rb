# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/source_definition"

RSpec.describe Dependabot::Job::SourceDefinition do
  describe ".from_hash" do
    subject(:definition) { described_class.from_hash(source_hash) }

    let(:source_hash) do
      {
        "provider" => "github",
        "repo" => "dependabot/dependabot-core",
        "directory" => "updater/../common",
        "directories" => nil,
        "branch" => "main",
        "commit" => "abc123",
        "hostname" => "github.example.com",
        "api-endpoint" => "https://github.example.com/api/v3"
      }
    end

    it "parses and normalizes the source" do
      expect(definition).to have_attributes(
        provider: "github",
        repo: "dependabot/dependabot-core",
        directory: "/common",
        directories: nil,
        branch: "main",
        commit: "abc123",
        hostname: "github.example.com",
        api_endpoint: "https://github.example.com/api/v3"
      )
    end

    context "with multiple directories" do
      let(:source_hash) do
        super().merge("directory" => nil, "directories" => ["one", "/two/../three"])
      end

      it "normalizes every directory" do
        expect(definition).to have_attributes(directory: nil, directories: ["/one", "/three"])
      end
    end

    context "with root directory" do
      let(:source_hash) { super().merge("directory" => "/") }

      it "preserves the root" do
        expect(definition.directory).to eq("/")
      end
    end

    context "with malformed optional fields" do
      let(:source_hash) do
        super().merge(
          "directory" => 1,
          "directories" => ["one", 2],
          "branch" => [],
          "commit" => {},
          "hostname" => true,
          "api-endpoint" => 3
        )
      end

      it "drops them" do
        expect(definition).to have_attributes(
          directory: nil,
          directories: nil,
          branch: nil,
          commit: nil,
          hostname: nil,
          api_endpoint: nil
        )
      end
    end

    context "without a provider" do
      let(:source_hash) { super().except("provider") }

      it "fails fast" do
        expect { definition }.to raise_error(KeyError)
      end
    end

    context "with a malformed repository" do
      let(:source_hash) { super().merge("repo" => nil) }

      it "fails fast" do
        expect { definition }.to raise_error(TypeError, /repo/)
      end
    end
  end

  describe "#to_source" do
    it "builds a Dependabot::Source" do
      definition = described_class.from_hash(
        {
          "provider" => "github",
          "repo" => "dependabot/dependabot-core",
          "directory" => "/common",
          "hostname" => "github.example.com",
          "api-endpoint" => "https://github.example.com/api/v3"
        }
      )

      expect(definition.to_source).to have_attributes(
        provider: "github",
        repo: "dependabot/dependabot-core",
        directory: "/common",
        hostname: "github.example.com",
        api_endpoint: "https://github.example.com/api/v3"
      )
    end
  end
end
