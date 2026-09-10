# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker/file_parser"
require "dependabot/docker/update_checker"
require "dependabot/package/release_cooldown_options"

# End-to-end regression guard for digest-only cooldown handling, built from a
# real multi-stage Dockerfile:
#
#   * /Dockerfile            -> FROM golang:alpine@sha256:f85330846cde... as builder
#   * .github/dependabot.yml -> package-ecosystem: docker, cooldown: default-days: 14
#
# When a new digest is pushed inside the configured cooldown window and the image
# is pinned by a non-comparable tag ("alpine"), the digest-only update bypasses the
# version-tag cooldown, so a PR could be raised anyway. This spec parses the
# Dockerfile with the real FileParser (guarding the digest-extraction path the
# cooldown logic relies on) and then asserts the UpdateChecker respects the cooldown.
RSpec.describe Dependabot::Docker::UpdateChecker do
  # Multi-stage Dockerfile pinning golang:alpine by digest, stored as a fixture.
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "multi_stage_non_comparable_tag_digest") }
  let(:dockerfile) { Dependabot::DependencyFile.new(name: "Dockerfile", content: dockerfile_body) }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "future-architect/vuls", directory: "/") }
  let(:parser) { Dependabot::Docker::FileParser.new(dependency_files: [dockerfile], source: source) }
  let(:dependencies) { parser.parse }
  let(:golang_dependency) { dependencies.find { |d| d.name == "golang" } }

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

  # Configured cooldown: default-days = 14.
  let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 14) }

  let(:mock_client) { instance_double(DockerRegistry2::Registry) }
  let(:last_modified) { (Time.now - (5 * 86_400)).httpdate }
  let(:blob_response) { instance_double(RestClient::Response, headers: { last_modified: last_modified }) }

  let(:checker) do
    described_class.new(
      dependency: golang_dependency,
      dependency_files: [dockerfile],
      credentials: credentials,
      ignored_versions: [],
      raise_on_ignored: false,
      update_cooldown: update_cooldown
    ).tap { |c| allow(c).to receive(:docker_registry_client).and_return(mock_client) }
  end

  before do
    allow(mock_client).to receive_messages(
      tags: { "tags" => %w(alpine 3.22 latest) },
      # A genuinely different, freshly-pushed digest.
      digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
      manifest_digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
      # Single-image manifest so multi-arch no-op detection fails open.
      manifest: { "mediaType" => "application/vnd.docker.distribution.manifest.v2+json" }
    )
    allow(mock_client).to receive(:dohead).and_return(blob_response)
    allow(Dependabot.logger).to receive(:info)
    allow(Dependabot.logger).to receive(:warn)
  end

  it "parses the Dockerfile into a digest-pinned golang:alpine dependency" do
    expect(dependencies.map(&:name)).to contain_exactly("golang", "alpine")
    expect(golang_dependency.requirements.first[:source]).to include(
      tag: "alpine",
      digest: "f85330846cde1e57ca9ec309382da3b8e6ae3ab943d2739500e08c86393a21b1"
    )
  end

  context "when the new digest is ~5 days old (inside the 14-day cooldown)" do
    let(:last_modified) { (Time.now - (5 * 86_400)).httpdate }

    it "does not propose the digest-only update (cooldown respected)" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
    end
  end

  context "when the new digest is 30 days old (older than the 14-day cooldown)" do
    let(:last_modified) { (Time.now - (30 * 86_400)).httpdate }

    it "proposes the digest-only update (cooldown elapsed)" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end
  end

  context "when the registry omits the Last-Modified header" do
    let(:blob_response) { instance_double(RestClient::Response, headers: {}) }

    before do
      stub_request(
        :get,
        "https://hub.docker.com/v2/namespaces/library/repositories/golang/tags/alpine"
      ).to_return(status: 404)
    end

    it "fails open and proposes the update" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end

    context "when the manifest digest lookup is rate limited" do
      before do
        attempts = 0
        allow(mock_client).to receive(:manifest_digest) do
          attempts += 1
          raise DockerRegistry2::RegistryHTTPException, "Registry request failed with status 429" if attempts == 1

          "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92"
        end
      end

      it "fails open when the subsequent digest resolution succeeds" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(golang_dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when Docker Hub reports a recent tag push" do
      before do
        stub_request(
          :get,
          "https://hub.docker.com/v2/namespaces/library/repositories/golang/tags/alpine"
        ).to_return(
          status: 200,
          body: {
            digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
            tag_last_pushed: (Time.now - (5 * 86_400)).iso8601
          }.to_json
        )
      end

      it "holds the digest-only update in cooldown" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(golang_dependency.metadata).not_to include(:cooldown_date_unavailable)
      end
    end

    context "when Docker Hub reports an old tag push" do
      before do
        stub_request(
          :get,
          "https://hub.docker.com/v2/namespaces/library/repositories/golang/tags/alpine"
        ).to_return(
          status: 200,
          body: {
            digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
            tag_last_pushed: (Time.now - (30 * 86_400)).iso8601
          }.to_json
        )
      end

      it "proposes the digest-only update" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end

      context "when the tag moves after its publication date is checked" do
        let(:checked_digest) { "98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92" }

        before do
          allow(mock_client).to receive(:manifest_digest)
            .and_return("sha256:#{checked_digest}", "sha256:#{'a' * 64}")
        end

        it "updates to the digest whose cooldown was checked" do
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
          expect(checker.updated_requirements.first.source_string("digest")).to eq(checked_digest)
          expect(mock_client).to have_received(:manifest_digest).once
        end
      end
    end
  end

  context "when GHCR omits the Last-Modified header" do
    let(:blob_response) { instance_double(RestClient::Response, headers: {}) }
    let(:dependency_tags) { ["latest"] }
    let(:golang_dependency) do
      Dependabot::Dependency.new(
        name: "astral-sh/uv",
        version: "latest",
        package_manager: "docker",
        requirements: dependency_tags.map do |tag|
          {
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { registry: "ghcr.io", tag: tag, digest: "old_digest" }
          }
        end
      )
    end
    let(:versions_url) { "https://api.github.com/orgs/astral-sh/packages/container/uv/versions" }
    let(:registry_digest) { "98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92" }
    let(:metadata_digest) { "sha256:#{registry_digest}" }
    let(:metadata_tags) { ["latest"] }
    let(:published_at) { (Time.now - (5 * 86_400)).iso8601 }
    let(:package_version) do
      {
        name: metadata_digest,
        updated_at: published_at,
        metadata: { container: { tags: metadata_tags } }
      }
    end
    let(:package_versions) { [package_version] }

    before do
      stub_request(:get, versions_url)
        .with(query: { "page" => "1", "per_page" => "100" })
        .to_return(status: 200, body: package_versions.to_json)
    end

    it "holds a recent digest-only update in cooldown" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      expect(golang_dependency.metadata).not_to include(:cooldown_date_unavailable)
    end

    context "when the publication date is outside cooldown" do
      let(:published_at) { (Time.now - (30 * 86_400)).iso8601 }

      it "proposes the digest-only update" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_string("digest")).to eq(registry_digest)
      end

      context "when the tag moves after the metadata lookup" do
        before do
          allow(mock_client).to receive(:manifest_digest)
            .and_return("sha256:#{registry_digest}", "sha256:#{'a' * 64}")
        end

        it "retains the digest whose cooldown was checked" do
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
          expect(checker.updated_requirements.first.source_string("digest")).to eq(registry_digest)
          expect(mock_client).to have_received(:manifest_digest).once
        end
      end
    end

    context "when the metadata digest is stale" do
      let(:metadata_digest) { "sha256:#{'b' * 64}" }

      it "fails open without using the mismatched date" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(golang_dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when the metadata does not include the tag" do
      let(:metadata_tags) { ["other"] }

      it "fails open without using a date for another tag" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(golang_dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when credentials contain only metadata for the credential proxy" do
      let(:credentials) do
        [
          Dependabot::Credential.new("type" => "git_source", "host" => "github.com"),
          Dependabot::Credential.new("type" => "docker_registry", "registry" => "ghcr.io")
        ]
      end

      it "requests metadata without a local token and enforces cooldown" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(WebMock).to have_requested(:get, versions_url)
          .with(query: { "page" => "1", "per_page" => "100" }) { |request| !request.headers.key?("Authorization") }
      end
    end

    context "when the package is owned by a user" do
      let(:user_versions_url) { "https://api.github.com/users/astral-sh/packages/container/uv/versions" }

      before do
        stub_request(:get, versions_url)
          .with(query: { "page" => "1", "per_page" => "100" }).to_return(status: 404)
        stub_request(:get, user_versions_url)
          .with(query: { "page" => "1", "per_page" => "100" })
          .to_return(status: 200, body: package_versions.to_json)
      end

      it "uses the user endpoint to enforce cooldown" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "when the metadata API rejects authentication" do
      before do
        stub_request(:get, versions_url)
          .with(query: { "page" => "1", "per_page" => "100" }).to_return(status: 403)
      end

      it "fails open with an unavailable-date warning" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(golang_dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when the matching version is beyond the first 500 results" do
      let(:package_versions) do
        Array.new(100) do |index|
          { name: "sha256:#{index.to_s(16).rjust(64, '0')}", metadata: { container: { tags: [] } } }
        end
      end

      before do
        (2..5).each do |page|
          stub_request(:get, versions_url)
            .with(query: { "page" => page.to_s, "per_page" => "100" })
            .to_return(status: 200, body: package_versions.to_json)
        end
        stub_request(:get, versions_url)
          .with(query: { "page" => "6", "per_page" => "100" })
          .to_return(status: 200, body: [package_version].to_json)
      end

      it "continues paginating and holds the recent digest in cooldown" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(WebMock).to have_requested(:get, versions_url)
          .with(query: { "page" => "6", "per_page" => "100" }).once
      end

      context "when the API is exhausted without a match" do
        before do
          stub_request(:get, versions_url)
            .with(query: { "page" => "6", "per_page" => "100" }).to_return(status: 200, body: "[]")
        end

        it "fails open after checking the final page" do
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
          expect(golang_dependency.metadata[:cooldown_date_unavailable]).to be(true)
          expect(WebMock).to have_requested(:get, versions_url)
            .with(query: { "page" => "6", "per_page" => "100" }).once
        end
      end
    end

    context "when a full page already contains the matching version" do
      let(:package_versions) { [package_version] + Array.new(99) { { name: "unrelated" } } }

      it "stops without requesting another page" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(WebMock).not_to have_requested(:get, versions_url)
          .with(query: { "page" => "2", "per_page" => "100" })
      end

      context "when another tag needs the next page" do
        let(:dependency_tags) { %w(latest stable) }

        before do
          stable_version = package_version.merge(metadata: { container: { tags: ["stable"] } })
          stub_request(:get, versions_url)
            .with(query: { "page" => "2", "per_page" => "100" })
            .to_return(status: 200, body: [stable_version].to_json)
        end

        it "reuses the first page and continues searching for the other tag" do
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
          expect(WebMock).to have_requested(:get, versions_url)
            .with(query: { "page" => "1", "per_page" => "100" }).once
          expect(WebMock).to have_requested(:get, versions_url)
            .with(query: { "page" => "2", "per_page" => "100" }).once
        end

        context "when the package is owned by a user" do
          let(:versions_url) { "https://api.github.com/users/astral-sh/packages/container/uv/versions" }

          before do
            stub_request(:get, "https://api.github.com/orgs/astral-sh/packages/container/uv/versions")
              .with(query: { "page" => "1", "per_page" => "100" }).to_return(status: 404)
          end

          it "continues pagination on the user endpoint" do
            expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
            expect(WebMock).to have_requested(:get, versions_url)
              .with(query: { "page" => "2", "per_page" => "100" }).once
          end
        end
      end
    end
  end
end
