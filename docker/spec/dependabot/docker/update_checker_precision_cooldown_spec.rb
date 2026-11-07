# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }
  let(:old_date) { (Time.now - (30 * 86_400)).iso8601 }
  let(:recent_date) { (Time.now - 86_400).iso8601 }
  let(:dates) { { "1.1.0" => recent_date, "1.1.0.1" => old_date } }
  let(:update_digest) { "b" * 64 }
  let(:digests) { { "1.0.0" => "a" * 64, "1.1.0" => update_digest, "1.1.0.1" => update_digest } }
  let(:metadata_url) { "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: "1.0.0",
      package_manager: package_manager,
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: { tag: "1.0.0" } }]
    )
  end
  let(:checker) do
    described_class.new(dependency: dependency, dependency_files: [], credentials: [], update_cooldown: cooldown)
  end
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:media_type) { "application/vnd.docker.distribution.manifest.v2+json" }
  let(:response) { instance_double(RestClient::Response, headers: { content_type: media_type }) }

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => digests.keys }, dohead: response)
    allow(registry).to receive(:manifest_digest) { |_repo, tag| "sha256:#{digests.fetch(tag)}" }
    digests.each do |tag, digest|
      stub_request(:get, metadata_url + tag).to_return(
        status: 200,
        body: { digest: "sha256:#{digest}", tag_last_pushed: dates.fetch(tag, old_date) }.to_json
      )
    end
  end

  shared_examples "cooldown-aware precision preference" do
    it "falls back to the eligible original candidate when its alias is too recent" do
      expect(checker.latest_version).to eq("1.1.0.1")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      expect(checker.updated_requirements.first.source_string("tag")).to eq("1.1.0.1")
      expect(WebMock).to have_requested(:get, metadata_url + "1.1.0").once
      expect(WebMock).to have_requested(:get, metadata_url + "1.1.0.1").once
    end

    context "when both aliases are eligible" do
      let(:dates) { {} }

      it "still prefers the same-precision alias without looking up the original publication date" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(WebMock).not_to have_requested(:get, metadata_url + "1.1.0.1")
      end
    end

    context "without cooldown" do
      let(:cooldown) { nil }

      it "preserves precision without fetching publication dates" do
        expect(checker.latest_version).to eq("1.1.0")
        digests.each_key { |tag| expect(WebMock).not_to have_requested(:get, metadata_url + tag) }
      end
    end

    context "when the original candidate is also too recent" do
      let(:dates) { { "1.1.0" => recent_date, "1.1.0.1" => recent_date } }

      it "does not bypass its cooldown" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "when the original candidate has no publication date" do
      let(:dates) { super().merge("1.1.0.1" => nil) }

      it "fails open for that candidate and records the unavailable date" do
        expect(checker.latest_version).to eq("1.1.0.1")
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when the preferred alias has no publication date" do
      let(:dates) { super().merge("1.1.0" => nil) }

      it "still allows the preferred alias and records the unavailable date" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when the original candidate is a no-op" do
      let(:update_digest) { "a" * 64 }

      it "still checks its contents after falling back" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "with a semver-specific cooldown" do
      let(:cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7, semver_minor_days: 40)
      end
      let(:dates) { { "1.1.0" => old_date, "1.1.0.1" => (Time.now - (60 * 86_400)).iso8601 } }

      it "uses the configured minor window for both tags" do
        expect(checker.latest_version).to eq("1.1.0.1")
      end
    end

    context "with timestamp validation" do
      let(:created) { Time.utc(2026, 1, 1).iso8601 }
      let(:config_response) { instance_double(Excon::Response, body: { created: created }.to_json) }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
        allow(registry).to receive_messages(
          manifest: { "mediaType" => media_type, "config" => { "digest" => "sha256:#{'e' * 64}" } },
          doget: config_response
        )
      end

      it "still rejects a fallback whose different image is not newer" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(registry).to have_received(:doget)
          .with("v2/library/example-image/blobs/sha256:#{'e' * 64}").at_least(:once)
      end
    end
  end

  it_behaves_like "cooldown-aware precision preference"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "cooldown-aware precision preference"
  end
end
