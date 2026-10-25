# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:current) { "1.0.0" }
  let(:highest) { "1.3.0" }
  let(:fallback) { "1.2.0" }
  let(:lower) { "1.1.0" }
  let(:tags) { [current, lower, fallback, highest] }
  let(:digests) { { current => "a" * 64, highest => "a" * 64, fallback => "b" * 64, lower => "c" * 64 } }
  let(:old_date) { (Time.now - (30 * 86_400)).iso8601 }
  let(:recent_date) { (Time.now - 86_400).iso8601 }
  let(:dates) { {} }
  let(:package_manager) { "docker" }
  let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: current,
      package_manager: package_manager,
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: { tag: current } }]
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency, dependency_files: [], credentials: [], update_cooldown: update_cooldown
    )
  end
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:response) do
    instance_double(
      RestClient::Response, headers: { content_type: "application/vnd.docker.distribution.manifest.v2+json" }
    )
  end
  let(:metadata_url) { "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/" }

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => tags }, dohead: response)
    allow(registry).to receive(:manifest_digest) { |_repo, tag| "sha256:#{digests.fetch(tag)}" }
    tags.each do |tag|
      stub_request(:get, metadata_url + tag).to_return(
        status: 200,
        body: { digest: "sha256:#{digests.fetch(tag)}", tag_last_pushed: dates.fetch(tag, old_date) }.to_json
      )
    end
  end

  shared_examples "cooldown-aware candidate fallback" do
    it "continues past a no-op to the highest eligible content update" do
      expect(checker.latest_version).to eq(fallback)
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      expect(checker.updated_requirements.first.source_string("tag")).to eq(fallback)
      expect(WebMock).not_to have_requested(:get, metadata_url + lower)
    end

    context "without cooldown" do
      let(:update_cooldown) { nil }

      it "still selects the content update without fetching publication dates" do
        expect(checker.latest_version).to eq(fallback)
        tags.each { |tag| expect(WebMock).not_to have_requested(:get, metadata_url + tag) }
      end
    end

    context "when the next content update is still in cooldown" do
      let(:dates) { { fallback => recent_date } }

      it "continues to an older eligible content update" do
        expect(checker.latest_version).to eq(lower)
        expect(checker.updated_requirements.first.source_string("tag")).to eq(lower)
      end

      context "when all content updates are in cooldown" do
        let(:dates) { { fallback => recent_date, lower => recent_date } }

        it "keeps the current version" do
          expect(checker.latest_version).to eq(current)
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end
    end

    context "when the no-op has no publication date" do
      let(:dates) { { highest => nil, fallback => recent_date } }

      it "fails open only for that tag and still checks the remaining candidates" do
        expect(checker.latest_version).to eq(lower)
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "with a semver-specific cooldown" do
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7, semver_minor_days: 40)
      end
      let(:dates) { { highest => (Time.now - (60 * 86_400)).iso8601, lower => old_date } }
      let(:lower) { "1.0.1" }

      it "checks each candidate's version delta rather than just the default window" do
        expect(checker.latest_version).to eq(lower)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the content update has no publication date" do
      let(:dates) { { fallback => nil } }

      it "fails open for the content update" do
        expect(checker.latest_version).to eq(fallback)
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "when the highest candidate has different contents" do
      let(:digests) { super().merge(highest => "d" * 64) }

      it "selects it without fetching publication dates for lower candidates" do
        expect(checker.latest_version).to eq(highest)
        expect(WebMock).not_to have_requested(:get, metadata_url + fallback)
      end
    end

    context "when multiple candidates are no-ops" do
      let(:digests) { super().merge(fallback => "a" * 64) }

      it "continues past all of them" do
        expect(checker.latest_version).to eq(lower)
      end
    end

    context "when the no-op is a rolling alias" do
      let(:current) { "3.10.0-eclipse-temurin-27-alpine" }
      let(:highest) { "3-eclipse-temurin-27-alpine" }
      let(:fallback) { "3.10.1-eclipse-temurin-27-alpine" }
      let(:tags) { [current, fallback, highest] }

      it "keeps searching for the newer pinned patch" do
        expect(checker.latest_version).to eq(fallback)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end
  end

  it_behaves_like "cooldown-aware candidate fallback"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "cooldown-aware candidate fallback"
  end
end
