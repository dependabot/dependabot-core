# typed: false
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
    expect(golang_dependency.requirements.first.source).to include(
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

    it "fails open and proposes the update" do
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end
  end
end
