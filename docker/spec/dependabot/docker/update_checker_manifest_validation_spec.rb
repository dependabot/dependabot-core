# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:tags) { %w(1.0.0 1.1.0) }
  let(:digests) { tags.to_h { |tag| [tag, digest] } }
  let(:digest) { "sha256:invalid" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: "1.0.0",
      package_manager: package_manager,
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: { tag: "1.0.0" } }]
    )
  end
  let(:checker) { described_class.new(dependency: dependency, dependency_files: [], credentials: []) }
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:response) do
    instance_double(
      RestClient::Response, headers: { content_type: "application/vnd.docker.distribution.manifest.v2+json" }
    )
  end

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => tags }, dohead: response)
    allow(registry).to receive(:manifest_digest) { |_repo, tag| digests.fetch(tag) }
  end

  shared_examples "inconclusive manifest digests" do
    ["sha256:", "sha256:invalid", "sha256:#{'a' * 63}", "sha256:#{'z' * 64}"].each do |invalid|
      context "when both tags return #{invalid.inspect}" do
        let(:digest) { invalid }

        it "does not treat the tags as identical" do
          expect(checker.latest_version).to eq("1.1.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        end
      end
    end

    context "when precision aliases have equal malformed digests" do
      let(:tags) { %w(1.0.0 1.1.0 1.1.0.1) }
      let(:digests) { { "1.0.0" => "sha256:#{'a' * 64}", "1.1.0" => digest, "1.1.0.1" => digest } }

      it "does not use them to substitute the same-precision alias" do
        expect(checker.latest_version).to eq("1.1.0.1")
      end
    end

    context "when the same valid digest uses different hex casing" do
      let(:digests) { { "1.0.0" => "sha256:#{'a' * 64}", "1.1.0" => "sha256:#{'A' * 64}" } }

      it "still recognizes identical manifests" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end
  end

  it_behaves_like "inconclusive manifest digests"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "inconclusive manifest digests"
  end
end
