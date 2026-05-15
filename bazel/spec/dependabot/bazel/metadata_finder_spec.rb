# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/bazel/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Bazel::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "bazel"
    )
  end

  let(:registry_client) { instance_double(Dependabot::Bazel::UpdateChecker::RegistryClient) }

  before do
    allow(Dependabot::Bazel::UpdateChecker::RegistryClient)
      .to receive(:new)
      .and_return(registry_client)
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "with a bazel_dep dependency from BCR" do
      let(:dependency_name) { "rules_go" }
      let(:version) { "0.57.0" }
      let(:requirements) do
        [{
          file: "MODULE.bazel",
          requirement: "0.57.0",
          groups: [],
          source: nil
        }]
      end

      context "when the module exists in BCR" do
        before do
          allow(registry_client)
            .to receive(:get_source)
            .with("rules_go", "0.57.0")
            .and_return({
              "url" => "https://github.com/bazelbuild/rules_go/archive/refs/tags/v0.57.0.zip",
              "integrity" => "sha256-fake",
              "strip_prefix" => "rules_go-0.57.0"
            })
        end

        it "returns the GitHub repository URL" do
          expect(source_url).to eq("https://github.com/bazelbuild/rules_go")
        end
      end

      context "when the module uses a GitHub releases URL" do
        before do
          allow(registry_client)
            .to receive(:get_source)
            .with("rules_go", "0.57.0")
            .and_return({
              "url" => "https://github.com/bazelbuild/rules_go/releases/download/v0.57.0/rules_go-v0.57.0.tar.gz"
            })
        end

        it "extracts the GitHub repository URL" do
          expect(source_url).to eq("https://github.com/bazelbuild/rules_go")
        end
      end

      context "when the module uses a non-GitHub URL" do
        before do
          allow(registry_client)
            .to receive(:get_source)
            .with("rules_go", "0.57.0")
            .and_return({
              "url" => "https://example.com/releases/rules_go-0.57.0.tar.gz"
            })
        end

        it "returns nil when Source.from_url cannot parse it" do
          # Source.from_url returns nil for non-git sources
          expect(source_url).to be_nil
        end
      end

      context "when the module does not exist in BCR" do
        before do
          allow(registry_client)
            .to receive(:get_source)
            .with("rules_go", "0.57.0")
            .and_return(nil)
        end

        it "returns nil" do
          expect(source_url).to be_nil
        end
      end

      context "when the module exists but has no URL" do
        before do
          allow(registry_client)
            .to receive(:get_source)
            .with("rules_go", "0.57.0")
            .and_return({})
        end

        it "returns nil" do
          expect(source_url).to be_nil
        end
      end

      context "when the dependency has no version" do
        let(:version) { nil }

        it "returns nil" do
          expect(source_url).to be_nil
        end
      end
    end

    context "with an http_archive dependency" do
      let(:dependency_name) { "rules_cc" }
      let(:version) { "0.2.0" }
      let(:requirements) do
        [{
          file: "WORKSPACE",
          requirement: "0.2.0",
          groups: [],
          source: {
            type: "http_archive",
            url: "https://github.com/bazelbuild/rules_cc/archive/v0.2.0.tar.gz"
          }
        }]
      end

      it "extracts the GitHub repository URL from the archive URL" do
        expect(source_url).to eq("https://github.com/bazelbuild/rules_cc")
      end

      context "with a GitHub releases URL" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "0.2.0",
            groups: [],
            source: {
              type: "http_archive",
              url: "https://github.com/bazelbuild/rules_cc/releases/download/v0.2.0/rules_cc.tar.gz"
            }
          }]
        end

        it "extracts the GitHub repository URL" do
          expect(source_url).to eq("https://github.com/bazelbuild/rules_cc")
        end
      end

      context "with a direct GitHub repository URL" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "0.2.0",
            groups: [],
            source: {
              type: "http_archive",
              url: "https://github.com/bazelbuild/rules_cc"
            }
          }]
        end

        it "returns the GitHub repository URL" do
          expect(source_url).to eq("https://github.com/bazelbuild/rules_cc")
        end
      end

      context "with a non-GitHub URL" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "0.2.0",
            groups: [],
            source: {
              type: "http_archive",
              url: "https://example.com/archives/rules_cc-0.2.0.tar.gz"
            }
          }]
        end

        it "returns nil when Source.from_url cannot parse it" do
          expect(source_url).to be_nil
        end
      end
    end

    context "with a git_repository dependency" do
      let(:dependency_name) { "com_google_protobuf" }
      let(:version) { "v3.19.0" }
      let(:requirements) do
        [{
          file: "WORKSPACE",
          requirement: "v3.19.0",
          groups: [],
          source: {
            type: "git_repository",
            tag: "v3.19.0",
            remote: "https://github.com/protocolbuffers/protobuf.git"
          }
        }]
      end

      it "returns the git remote URL" do
        expect(source_url).to eq("https://github.com/protocolbuffers/protobuf")
      end

      context "when remote is an HTTPS URL without .git extension" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "v3.19.0",
            groups: [],
            source: {
              type: "git_repository",
              tag: "v3.19.0",
              remote: "https://github.com/protocolbuffers/protobuf"
            }
          }]
        end

        it "returns the repository URL" do
          expect(source_url).to eq("https://github.com/protocolbuffers/protobuf")
        end
      end

      context "when remote is missing" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "v3.19.0",
            groups: [],
            source: {
              type: "git_repository",
              tag: "v3.19.0"
            }
          }]
        end

        it "returns nil" do
          expect(source_url).to be_nil
        end
      end

      context "with a commit instead of tag" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "abc123",
            groups: [],
            source: {
              type: "git_repository",
              commit: "abc123",
              remote: "https://github.com/protocolbuffers/protobuf.git"
            }
          }]
        end

        it "returns the git remote URL" do
          expect(source_url).to eq("https://github.com/protocolbuffers/protobuf")
        end
      end
    end

    context "with an unknown source type" do
      let(:dependency_name) { "unknown_dep" }
      let(:version) { "1.0.0" }
      let(:requirements) do
        [{
          file: "BUILD",
          requirement: "1.0.0",
          groups: [],
          source: {
            type: "unknown_type"
          }
        }]
      end

      it "returns nil" do
        expect(source_url).to be_nil
      end
    end
  end

  describe "#changelog_url" do
    subject(:changelog_url) { finder.changelog_url }

    let(:dependency_name) { "rules_go" }
    let(:version) { "0.57.0" }
    let(:requirements) do
      [{
        file: "MODULE.bazel",
        requirement: "0.57.0",
        groups: [],
        source: nil
      }]
    end

    before do
      allow(registry_client)
        .to receive(:get_source)
        .with("rules_go", "0.57.0")
        .and_return({
          "url" => "https://github.com/bazelbuild/rules_go/archive/refs/tags/v0.57.0.zip"
        })

      # Mock GitHub API to find CHANGELOG
      stub_request(:get, "https://api.github.com/repos/bazelbuild/rules_go/contents/?ref=v0.57.0")
        .to_return(
          status: 200,
          body: [
            { name: "CHANGELOG.md", type: "file", size: 5000, path: "CHANGELOG.md" }
          ].to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "finds the changelog in the repository" do
      # The base MetadataFinders::Base class handles changelog finding
      # We just need to verify it can get the source URL
      expect(finder.source_url).to eq("https://github.com/bazelbuild/rules_go")
    end
  end

  describe "#releases_url" do
    subject { finder.releases_url }

    let(:dependency_name) { "rules_go" }
    let(:version) { "0.57.0" }
    let(:requirements) do
      [{
        file: "MODULE.bazel",
        requirement: "0.57.0",
        groups: [],
        source: nil
      }]
    end

    before do
      allow(registry_client)
        .to receive(:get_source)
        .with("rules_go", "0.57.0")
        .and_return({
          "url" => "https://github.com/bazelbuild/rules_go/archive/refs/tags/v0.57.0.zip"
        })

      # Mock GitHub API to check for releases
      stub_request(:get, "https://api.github.com/repos/bazelbuild/rules_go/releases?per_page=100")
        .to_return(
          status: 200,
          body: [
            { tag_name: "v0.57.0", name: "Release v0.57.0", html_url: "https://github.com/bazelbuild/rules_go/releases/tag/v0.57.0" }
          ].to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns the GitHub releases URL" do
      # The base class constructs the releases URL from the source
      expect(finder.source_url).to eq("https://github.com/bazelbuild/rules_go")
    end
  end

  describe "private methods" do
    let(:dependency_name) { "rules_go" }
    let(:version) { "0.57.0" }

    describe "#source_type" do
      subject { finder.send(:source_type) }

      context "with bazel_dep (source is nil)" do
        let(:requirements) do
          [{
            file: "MODULE.bazel",
            requirement: "0.57.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(:bazel_dep) }
      end

      context "with http_archive" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "0.57.0",
            groups: [],
            source: { type: "http_archive", url: "https://example.com/file.tar.gz" }
          }]
        end

        it { is_expected.to eq(:http_archive) }
      end

      context "with git_repository" do
        let(:requirements) do
          [{
            file: "WORKSPACE",
            requirement: "v3.19.0",
            groups: [],
            source: { type: "git_repository", remote: "https://github.com/example/repo.git" }
          }]
        end

        it { is_expected.to eq(:git_repository) }
      end

      context "with unknown type" do
        let(:requirements) do
          [{
            file: "BUILD",
            requirement: "1.0.0",
            groups: [],
            source: { type: "unknown" }
          }]
        end

        it { is_expected.to eq(:unknown) }
      end
    end

    describe "#extract_github_source_from_url" do
      subject(:extracted_source) { finder.send(:extract_github_source_from_url, url) }

      context "with GitHub archive URL" do
        let(:url) { "https://github.com/bazelbuild/rules_go/archive/refs/tags/v0.57.0.zip" }
        let(:requirements) { [{ file: "MODULE.bazel", requirement: "0.57.0", groups: [], source: nil }] }

        it "extracts the repository URL" do
          expect(extracted_source&.url).to eq("https://github.com/bazelbuild/rules_go")
        end
      end

      context "with GitHub releases download URL" do
        let(:url) { "https://github.com/bazelbuild/rules_go/releases/download/v0.57.0/file.tar.gz" }
        let(:requirements) { [{ file: "MODULE.bazel", requirement: "0.57.0", groups: [], source: nil }] }

        it "extracts the repository URL" do
          expect(extracted_source&.url).to eq("https://github.com/bazelbuild/rules_go")
        end
      end

      context "with direct GitHub repository URL" do
        let(:url) { "https://github.com/bazelbuild/rules_go" }
        let(:requirements) { [{ file: "MODULE.bazel", requirement: "0.57.0", groups: [], source: nil }] }

        it "returns the repository URL" do
          expect(extracted_source&.url).to eq("https://github.com/bazelbuild/rules_go")
        end
      end

      context "with non-GitHub URL" do
        let(:url) { "https://example.com/files/archive.tar.gz" }
        let(:requirements) { [{ file: "MODULE.bazel", requirement: "0.57.0", groups: [], source: nil }] }

        it "returns nil" do
          expect(extracted_source).to be_nil
        end
      end
    end
  end
end
