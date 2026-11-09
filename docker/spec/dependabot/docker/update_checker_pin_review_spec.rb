# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }] }
  let(:digests) { { "1.0.0" => "a" * 64, "1.1.0" => "b" * 64 } }
  let(:cooldown) { nil }
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
  let(:unknown_error) { DockerRegistry2::RegistryHTTPException.new("Registry request failed") }
  let(:media_type) { "application/vnd.oci.image.index.v1+json" }
  let(:response) { instance_double(RestClient::Response, headers: { content_type: media_type }) }
  let(:platforms) do
    [{ "platform" => { "os" => "linux", "architecture" => "amd64" }, "digest" => "sha256:#{'d' * 64}" }]
  end

  before do
    Dependabot::Experiments.register(:docker_digest_only_update_suppression, true)
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(
      tags: { "tags" => digests.keys },
      dohead: response,
      manifest: { "mediaType" => media_type, "manifests" => platforms }
    )
    allow(registry).to receive(:manifest_digest) do |_repo, tag|
      digest = digests.fetch(tag)
      digest && "sha256:#{digest}"
    end
    digests.each do |tag, digest|
      stub_request(:get, "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/#{tag}")
        .to_return(
          status: 200, body: { digest: "sha256:#{digest}", tag_last_pushed: (Time.now - 2_592_000).iso8601 }.to_json
        )
    end
  end

  shared_examples "pin refreshes and no-op candidates" do
    it "skips different indexes with identical platforms when the current pin is current" do
      expect(checker.latest_version).to eq("1.0.0")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
    end

    context "with a stale pin" do
      let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }

      it "keeps the version candidate to refresh the pin" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.1.0", digest: "b" * 64)
      end
    end

    context "when a second matching requirement has a stale pin" do
      let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }, { tag: "1.0.0", digest: "c" * 64 }] }

      it "does not let the current pin hide the stale pin" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the source already pins the candidate index" do
      let(:sources) { [{ tag: "1.0.0", digest: "b" * 64 }] }

      it "does not propose a tag-only update" do
        expect(checker.latest_version).to eq("1.0.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
      end
    end

    context "when the current digest has an unparseable registry error" do
      let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }

      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.0.0")
                                                    .and_raise(unknown_error)
      end

      it "keeps the candidate when pin comparison is inconclusive" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the current registry digest is malformed" do
      let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }
      let(:digests) { super().merge("1.0.0" => "invalid") }

      it "keeps the candidate when the stale pin cannot be verified" do
        expect(checker.latest_version).to eq("1.1.0")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "when the candidate digest has an unparseable registry error" do
      let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }

      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.1.0")
                                                    .and_raise(unknown_error)
      end

      it "keeps the candidate when pin comparison is inconclusive" do
        expect(checker.latest_version).to eq("1.1.0")
      end
    end

    context "when precision comparison has no digests" do
      let(:digests) { { "1.0.0" => nil, "1.0.0.1" => nil } }
      let(:sources) { [{ tag: "1.0.0" }] }
      let(:platforms) { [] }

      it "does not treat missing digests as evidence of matching aliases" do
        expect(checker.latest_version).to eq("1.0.0.1")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
      end
    end

    context "with a more precise candidate matching the current tag" do
      let(:digests) { { "1.0.0" => "a" * 64, "1.0.0.1" => "a" * 64 } }
      let(:sources) { [{ tag: "1.0.0", digest: "c" * 64 }] }
      let(:cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }

      it "keeps the more precise candidate rather than hiding the pin refresh" do
        expect(checker.latest_version).to eq("1.0.0.1")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.updated_requirements.first.source_hash).to eq(tag: "1.0.0.1", digest: "a" * 64)
      end

      context "with creation timestamp validation enabled" do
        before { Dependabot::Experiments.register(:docker_created_timestamp_validation, true) }

        it "allows the confirmed identical manifest to refresh the pin" do
          expect(checker.latest_version).to eq("1.0.0.1")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        end
      end

      context "when the pin is current" do
        let(:sources) { [{ tag: "1.0.0", digest: "a" * 64 }] }

        it "continues to prefer the current tag" do
          expect(checker.latest_version).to eq("1.0.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end

      context "when the more precise candidate is in cooldown" do
        before do
          stub_request(:get, "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/1.0.0.1")
            .to_return(status: 200, body: { digest: "sha256:#{'a' * 64}", tag_last_pushed: Time.now.iso8601 }.to_json)
        end

        it "does not bypass the candidate's cooldown" do
          expect(checker.latest_version).to eq("1.0.0")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        end
      end
    end
  end

  it_behaves_like "pin refreshes and no-op candidates"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "pin refreshes and no-op candidates"
  end
end
