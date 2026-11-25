# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:tags) { %w(1.0.0 1.1.0) }
  let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }
  let(:package_manager) { "docker" }
  let(:suppression) { true }
  let(:cooldown) { nil }
  let(:candidate_date) { (Time.now - (30 * 86_400)).iso8601 }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: "1.0.0",
      package_manager: package_manager,
      requirements: sources.each_with_index.map do |source, index|
        { requirement: nil, groups: [], file: "Dockerfile.#{index}", source: source }
      end
    )
  end
  let(:checker) do
    described_class.new(dependency: dependency, dependency_files: [], credentials: [], update_cooldown: cooldown)
  end
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:media_type) { "application/vnd.docker.distribution.manifest.v2+json" }
  let(:response) { instance_double(RestClient::Response, headers: { content_type: media_type }) }

  before do
    Dependabot::Experiments.register(:docker_digest_only_update_suppression, suppression)
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(
      tags: { "tags" => tags },
      dohead: response,
      manifest: { "mediaType" => media_type },
      manifest_digest: "sha256:#{'a' * 64}"
    )
    tags.each do |tag|
      stub_request(:get, "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/#{tag}")
        .to_return(
          status: 200,
          body: {
            digest: "sha256:#{'a' * 64}",
            tag_last_pushed: tag == "1.1.0" ? candidate_date : (Time.now - (30 * 86_400)).iso8601
          }.to_json
        )
    end
  end

  shared_examples "pinned updates with identical tag contents" do
    it "keeps a version update eligible to replace the stale pin" do
      expect(checker.latest_version).to eq("1.1.0")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.1.0", digest: "a" * 64)
    end

    context "without digest-only suppression" do
      let(:suppression) { false }

      it "retains the existing digest-only refresh without changing tags" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.0.0", digest: "a" * 64)
      end
    end

    context "when the pin is already current" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }] }

      it "does not propose a tag-only no-op" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "without a digest pin" do
      let(:sources) { [{ tag: "1.0.0" }] }

      it "still skips identical aliases" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "with multiple pins for the same tag" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }, { tag: "1.0.0", digest: "c" * 64 }] }

      it "does not let a current pin hide another stale pin" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.map(&:source_hash)).to all(eq(tag: "1.1.0", digest: "a" * 64))
      end
    end

    context "when only a different source tag has a stale pin" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }, { tag: "0.9.0", digest: "c" * 64 }] }

      it "does not use that pin to keep a no-op candidate for the current tag" do
        expect(checker.latest_version).to eq("1.0.0")
      end
    end

    context "without a newer version" do
      let(:tags) { ["1.0.0"] }

      it "still respects digest-only suppression" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "with cooldown" do
      let(:cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

      it "allows the eligible version and digest update" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end

      context "when the candidate is still in cooldown" do
        let(:candidate_date) { (Time.now - 86_400).iso8601 }

        it "does not bypass cooldown to update the pin" do
          expect(checker.latest_version).to eq("1.0.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end
    end
  end

  it_behaves_like "pinned updates with identical tag contents"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "pinned updates with identical tag contents"
  end
end
