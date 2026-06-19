# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker/file_parser"
require "dependabot/docker/update_checker"
require "dependabot/package/release_cooldown_options"

# End-to-end regression guard for
# https://github.com/dependabot/dependabot-core/issues/14072 built from the
# original reporter's real repository (future-architect/vuls):
#
#   * /Dockerfile            -> FROM golang:alpine@sha256:f85330846cde... as builder
#   * .github/dependabot.yml -> package-ecosystem: docker, cooldown: default-days: 14
#
# In the issue the new digest was pushed ~5 days before Dependabot opened the PR,
# well inside the configured 14-day cooldown. Because "alpine" is a non-comparable
# tag pinned by digest, the digest-only update bypassed the version-tag cooldown
# and a PR was raised anyway. This spec parses the reporter's actual Dockerfile
# with the real FileParser (guarding the digest-extraction path the cooldown logic
# relies on) and then asserts the UpdateChecker now respects the cooldown.
RSpec.describe Dependabot::Docker::UpdateChecker do
  # Verbatim content of future-architect/vuls /Dockerfile, stored as a fixture.
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "vuls_issue_14072") }
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

  # Reporter's real config: cooldown.default-days = 14.
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
      # A genuinely different, freshly-pushed digest (stands in for the issue's new digest).
      digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
      manifest_digest: "sha256:98e6cffc31ccc44c7c15d83df1d69891efee8115a5bb7ede2bf30a38af3e3c92",
      # Single-image manifest so multi-arch no-op detection fails open.
      manifest: { "mediaType" => "application/vnd.docker.distribution.manifest.v2+json" }
    )
    allow(mock_client).to receive(:dohead).and_return(blob_response)
    allow(Dependabot.logger).to receive(:info)
    allow(Dependabot.logger).to receive(:warn)
  end

  it "parses the reporter's Dockerfile into a digest-pinned golang:alpine dependency" do
    expect(dependencies.map(&:name)).to contain_exactly("golang", "alpine")
    expect(golang_dependency.requirements.first[:source]).to include(
      tag: "alpine",
      digest: "f85330846cde1e57ca9ec309382da3b8e6ae3ab943d2739500e08c86393a21b1"
    )
  end

  context "when the new digest is ~5 days old (inside the 14-day cooldown, as in the issue)" do
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
