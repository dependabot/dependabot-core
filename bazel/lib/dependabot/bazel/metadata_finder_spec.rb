# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/source"
require "dependabot/bazel/metadata_finder"

RSpec.describe Dependabot::Bazel::MetadataFinder do
  let(:dependency_name) { "example_dep" }
  let(:version) { "1.0.0" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "bazel"
    )
  end

  let(:finder) do
    described_class.new(
      dependency: dependency,
      credentials: []
    )
  end

  describe "#source_from_url" do
    context "with a GitHub archive URL" do
      let(:requirements) do
        [
          {
            file: "MODULE.bazel",
            source: {
              type: "http_archive",
              url: "https://github.com/example-org/example-repo/archive/v1.0.0.tar.gz"
            }
          }
        ]
      end

      it "extracts the GitHub repository source" do
        source = finder.send(:source_from_url, requirements.first[:source][:url])

        expect(source).to be_a(Dependabot::Source)
        expect(source.url).to eq("https://github.com/example-org/example-repo")
      end
    end

    context "with a GitHub releases URL ending in .git" do
      let(:requirements) do
        [
          {
            file: "MODULE.bazel",
            source: {
              type: "http_archive",
              url: "https://github.com/example-org/example-repo.git/releases/download/v1.0.0/foo.tar.gz"
            }
          }
        ]
      end

      it "normalizes the repo name by stripping .git" do
        source = finder.send(:source_from_url, requirements.first[:source][:url])

        expect(source).to be_a(Dependabot::Source)
        expect(source.url).to eq("https://github.com/example-org/example-repo")
      end
    end

    context "with a non-GitHub URL" do
      let(:requirements) do
        [
          {
            file: "MODULE.bazel",
            source: {
              type: "http_archive",
              url: "https://example.com/example-repo.tar.gz"
            }
          }
        ]
      end

      it "falls back to Dependabot::Source.from_url" do
        source = finder.send(:source_from_url, requirements.first[:source][:url])

        expect(source).to be_a(Dependabot::Source)
        expect(source.url).to eq("https://example.com/example-repo.tar.gz")
      end
    end
  end
end
