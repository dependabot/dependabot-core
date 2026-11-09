# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:sources) { [{ tag: "1.0.0", digest: "b" * 64 }] }
  let(:current_digest) { nil }
  let(:candidate_digest) { "b" * 64 }
  let(:digests) { { "1.0.0" => current_digest, "1.1.0" => "c" * 64, "1.2.0" => candidate_digest } }
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
  let(:checker) { described_class.new(dependency: dependency, dependency_files: [], credentials: []) }
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:media_type) { "application/vnd.oci.image.index.v1+json" }
  let(:response) { instance_double(RestClient::Response, headers: { content_type: media_type }) }

  before do
    Dependabot::Experiments.register(:docker_digest_only_update_suppression, true)
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => digests.keys }, dohead: response)
    allow(registry).to receive(:manifest_digest) do |_repo, tag|
      digest = digests.fetch(tag)
      digest && "sha256:#{digest}"
    end
    allow(registry).to receive(:manifest) do |_repo, tag|
      platform_digest = tag == "1.1.0" ? "e" * 64 : "d" * 64
      {
        "mediaType" => media_type,
        "manifests" => [{ "platform" => { "os" => "linux", "architecture" => "amd64" },
                          "digest" => "sha256:#{platform_digest}" }]
      }
    end
  end

  shared_examples "unavailable current digest" do
    it "skips the already pinned candidate and selects the different-content version" do
      expect(checker.latest_version).to eq("1.1.0")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.1.0", digest: "c" * 64)
    end

    context "when the current digest is malformed" do
      let(:current_digest) { "invalid" }

      it "continues to the different-content candidate" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the current digest lookup raises" do
      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.0.0")
                                                    .and_raise(DockerRegistry2::RegistryHTTPException.new("error"))
      end

      it "continues to the different-content candidate" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when another pin differs from the candidate" do
      let(:sources) { [{ tag: "1.0.0", digest: "b" * 64 }, { tag: "1.0.0", digest: "a" * 64 }] }

      it "keeps the candidate to refresh that pin" do
        expect(checker.latest_version).to eq("1.2.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the candidate digest is unavailable" do
      let(:candidate_digest) { nil }

      it "retains the candidate when the pin comparison is inconclusive" do
        expect(checker.latest_version).to eq("1.2.0")
      end
    end
  end

  it_behaves_like "unavailable current digest"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "unavailable current digest"
  end
end
