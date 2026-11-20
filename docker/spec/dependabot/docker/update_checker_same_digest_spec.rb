# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:current) { "3.10.0-eclipse-temurin-27-alpine" }
  let(:candidate) { "3-eclipse-temurin-27-alpine" }
  let(:newer) { "3.10.1-eclipse-temurin-27-alpine" }
  let(:tags) { [current, candidate] }
  let(:current_digest) { "a" * 64 }
  let(:candidate_digest) { current_digest }
  let(:digests) { { current => current_digest, candidate => candidate_digest, newer => "b" * 64 } }
  let(:source) { { tag: current } }
  let(:package_manager) { "docker" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: current,
      package_manager: package_manager,
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: source }]
    )
  end
  let(:checker) { described_class.new(dependency: dependency, dependency_files: [], credentials: []) }
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:headers) { { content_type: "application/vnd.docker.distribution.manifest.v2+json" } }
  let(:response) { instance_double(RestClient::Response, headers: headers) }

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => tags }, dohead: response)
    allow(registry).to receive(:manifest_digest) do |_repo, tag|
      "sha256:#{digests.fetch(tag)}"
    end
  end

  shared_examples "same-digest tag updates" do
    it "keeps the current tag when the rolling candidate has the same digest" do
      expect(checker.latest_version).to eq(current)
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      expect(checker.updated_requirements.first.source_string("tag")).to eq(current)
    end

    context "with the same tag precision" do
      let(:current) { "1.2.0" }
      let(:candidate) { "1.3.0" }

      it "does not propose an identical image" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "with a more precise candidate" do
      let(:current) { "1.2.0" }
      let(:candidate) { "1.3.0.1" }

      it "does not propose an identical image" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "when a different-digest update sorts below a same-digest rolling alias" do
      let(:candidate) { "3.10-eclipse-temurin-27-alpine" }
      let(:tags) { [current, candidate, newer] }

      it "continues searching and selects the real update" do
        expect(checker.latest_version).to eq(newer)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the candidate has different contents" do
      let(:candidate_digest) { "b" * 64 }

      it "allows the update" do
        expect(checker.latest_version).to eq(candidate)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the file pins an older digest" do
      let(:source) { { tag: current, digest: "c" * 64 } }

      before { allow(registry).to receive(:manifest).and_return("mediaType" => headers.fetch(:content_type)) }

      it "still updates the pinned digest without changing tags" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_hash).to eq(tag: current, digest: current_digest)
      end
    end

    context "when the file already pins the identical digest" do
      let(:source) { { tag: current, digest: current_digest } }

      it "does not offer an update" do
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end
  end

  it_behaves_like "same-digest tag updates"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "same-digest tag updates"
  end
end
