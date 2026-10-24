# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker/update_checker"

RSpec.describe Dependabot::Docker::UpdateChecker do
  subject(:same_contents) { checker.send(:same_image_contents?, candidate_tag, current_tag) }

  let(:current_tag) { Dependabot::Docker::Tag.new("1.0.0") }
  let(:candidate_tag) { Dependabot::Docker::Tag.new("1.1.0") }
  let(:current_digest) { "sha256:#{'a' * 64}" }
  let(:candidate_digest) { current_digest }
  let(:registry) { instance_double(DockerRegistry2::Registry) }
  let(:response) do
    instance_double(RestClient::Response, headers: { content_type: media_type })
  end
  let(:media_type) { "application/vnd.docker.distribution.manifest.v2+json" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "example-image",
      version: current_tag.name,
      package_manager: "docker",
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: { tag: current_tag.name } }]
    )
  end
  let(:checker) { described_class.new(dependency: dependency, dependency_files: [], credentials: []) }

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => [current_tag.name, candidate_tag.name] }, dohead: response)
    allow(registry).to receive(:manifest_digest).with("library/example-image", current_tag.name)
                                                .and_return(current_digest)
    allow(registry).to receive(:manifest_digest).with("library/example-image", candidate_tag.name)
                                                .and_return(candidate_digest)
  end

  it "recognizes identical single-platform manifests without a content-type lookup" do
    expect(same_contents).to be(true)
    expect(registry).not_to have_received(:dohead)
  end

  it "reuses cached manifest digests" do
    2.times { expect(checker.send(:same_image_contents?, candidate_tag, current_tag)).to be(true) }
    expect(registry).to have_received(:manifest_digest).with("library/example-image", current_tag.name).once
    expect(registry).to have_received(:manifest_digest).with("library/example-image", candidate_tag.name).once
  end

  context "with different single-platform digests" do
    let(:candidate_digest) { "sha256:#{'b' * 64}" }

    it { is_expected.to be(false) }
  end

  [nil, "", "sha256:"].each do |missing_digest|
    context "when both digests are #{missing_digest.inspect}" do
      let(:current_digest) { missing_digest }

      it "does not mistake missing information for identical contents" do
        expect(same_contents).to be(false)
      end
    end
  end

  context "when only the candidate digest is missing" do
    let(:candidate_digest) { nil }

    it { is_expected.to be(false) }
  end

  {
    authentication: DockerRegistry2::RegistryAuthenticationException.new,
    authorization: DockerRegistry2::RegistryAuthorizationException.new,
    not_found: DockerRegistry2::NotFound.new,
    transient: DockerRegistry2::RegistryUnknownException.new,
    rate_limit: DockerRegistry2::RegistryHTTPException.new("Registry request failed with status 429")
  }.each do |reason, error|
    context "when a digest lookup fails (#{reason})" do
      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", current_tag.name)
                                                    .and_raise(error)
      end

      it "does not classify the candidate as a no-op" do
        expect(same_contents).to be(false)
      end

      it "preserves the tag-only update path" do
        expect(checker.latest_version).to eq(candidate_tag.name)
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end
  end

  context "with multi-platform indexes" do
    let(:media_type) { "application/vnd.oci.image.index.v1+json" }
    let(:platform_manifest) do
      { "platform" => { "os" => "linux", "architecture" => "amd64" }, "digest" => "sha256:#{'d' * 64}" }
    end
    let(:candidate_manifests) { [platform_manifest] }

    before do
      allow(registry).to receive(:manifest).with("library/example-image", current_tag.name)
                                           .and_return("mediaType" => media_type, "manifests" => [platform_manifest])
      allow(registry).to receive(:manifest).with("library/example-image", candidate_tag.name)
                                           .and_return("mediaType" => media_type, "manifests" => candidate_manifests)
    end

    it "recognizes identical index digests without downloading manifests" do
      expect(same_contents).to be(true)
      expect(registry).not_to have_received(:manifest)
    end

    context "when the index digests differ" do
      let(:candidate_digest) { "sha256:#{'b' * 64}" }

      it "retains suppression for identical per-platform contents" do
        expect(same_contents).to be(true)
        expect(registry).to have_received(:manifest).with("library/example-image", candidate_tag.name)
      end

      context "when the candidate adds a platform" do
        let(:candidate_manifests) do
          [platform_manifest,
           { "platform" => { "os" => "linux", "architecture" => "arm64" }, "digest" => "sha256:#{'e' * 64}" }]
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
