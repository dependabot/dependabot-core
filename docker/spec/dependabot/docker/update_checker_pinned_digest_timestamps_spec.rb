# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:tags) { %w(1.0.0 1.1.0) }
  let(:digests) { { "1.0.0" => "a" * 64, "1.1.0" => "a" * 64 } }
  let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }
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
  let(:created) { Time.utc(2026, 1, 1).iso8601 }
  let(:config_response) { instance_double(Excon::Response, body: { created: created }.to_json) }

  before do
    Dependabot::Experiments.register(:docker_digest_only_update_suppression, suppression)
    Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(
      tags: { "tags" => tags },
      dohead: response,
      manifest: { "mediaType" => media_type, "config" => { "digest" => "sha256:#{'e' * 64}" } },
      doget: config_response
    )
    allow(registry).to receive(:manifest_digest) do |_repo, tag|
      digest = digests.fetch(tag)
      digest.nil? || digest.empty? ? digest : "sha256:#{digest}"
    end
    tags.each do |tag|
      stub_request(:get, "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/#{tag}")
        .to_return(
          status: 200, body: { digest: "sha256:#{digests.fetch(tag)}", tag_last_pushed: candidate_date }.to_json
        )
    end
  end

  shared_examples "stale pins with timestamp validation" do
    it "allows a confirmed identical-manifest candidate to refresh the stale pin" do
      expect(checker.latest_version).to eq("1.1.0")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.1.0", digest: "a" * 64)
    end

    context "when a current pin accompanies a stale pin" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }, { tag: "1.0.0", digest: "c" * 64 }] }

      it "refreshes the stale pin despite the identical creation timestamps" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.map(&:source_hash)).to all(eq(tag: "1.1.0", digest: "a" * 64))
      end
    end

    context "when the pin is current" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }] }

      it "still rejects a tag-only no-op" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "without a pin" do
      let(:sources) { [{ tag: "1.0.0" }] }

      it "still rejects a tag-only no-op" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "without suppression" do
      let(:suppression) { false }

      it "retains the digest-only update without changing tags" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.0.0", digest: "a" * 64)
      end
    end

    context "without a newer tag" do
      let(:tags) { ["1.0.0"] }

      it "retains digest-only suppression" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "with different manifest digests" do
      let(:digests) { super().merge("1.1.0" => "b" * 64) }

      it "does not bypass timestamp validation just because the pin is stale" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(registry).to have_received(:doget)
          .with("v2/library/example-image/blobs/sha256:#{'e' * 64}").at_least(:once)
      end
    end

    [nil, ""].each do |digest|
      context "with an inconclusive current manifest digest (#{digest.inspect})" do
        let(:digests) { super().merge("1.0.0" => digest) }

        it "does not treat an unconfirmed match as a timestamp exception" do
          expect(checker.latest_version).to eq("1.0.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end
    end

    context "when the current digest lookup fails" do
      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.0.0")
                                                    .and_raise(DockerRegistry2::RegistryUnknownException)
      end

      it "still requires timestamp validation" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "when the timestamp validation budget is exhausted" do
      let(:tags) { super() + %w(1.2.0 1.3.0 1.4.0 1.5.0 1.6.0) }
      let(:digests) { super().merge(tags.drop(2).to_h { |tag| [tag, "b" * 64] }) }

      it "still permits the confirmed identical-manifest refresh" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "with cooldown" do
      let(:cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

      it "allows the eligible digest refresh" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end

      context "when the candidate was published recently" do
        let(:candidate_date) { (Time.now - 86_400).iso8601 }

        it "does not bypass cooldown to refresh the pin" do
          expect(checker.latest_version).to eq("1.0.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end
    end
  end

  it_behaves_like "stale pins with timestamp validation"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "stale pins with timestamp validation"
  end
end
