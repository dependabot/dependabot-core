# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker_compose"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:package_manager) { "docker" }
  let(:cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7) }
  let(:candidate_digest) { "b" * 64 }
  let(:candidate_date) { (Time.now - (30 * 86_400)).iso8601 }
  let(:digests) { { "1.0.0" => "a" * 64, "1.1.0" => "a" * 64, "1.1.0.1" => candidate_digest } }
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
  let(:response) do
    instance_double(
      RestClient::Response, headers: { content_type: "application/vnd.docker.distribution.manifest.v2+json" }
    )
  end

  before do
    allow(checker).to receive(:docker_registry_client).and_return(registry)
    allow(registry).to receive_messages(tags: { "tags" => digests.keys }, dohead: response)
    allow(registry).to receive(:manifest_digest) { |_repo, tag| "sha256:#{digests.fetch(tag)}" }
    digests.each do |tag, digest|
      stub_request(:get, "https://hub.docker.com/v2/namespaces/library/repositories/example-image/tags/#{tag}")
        .to_return(
          status: 200,
          body: { digest: "sha256:#{digest}", tag_last_pushed: candidate_date }.to_json
        )
    end
  end

  shared_examples "optional precision comparison" do
    it "selects the highest eligible candidate when lookups succeed" do
      expect(checker.latest_version).to eq("1.1.0.1")
      expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    end

    {
      authentication: DockerRegistry2::RegistryAuthenticationException.new,
      transient: DockerRegistry2::RegistryUnknownException.new,
      rate_limit: DockerRegistry2::RegistryHTTPException.new("Registry request failed with status 429")
    }.each do |reason, error|
      context "when the same-precision lookup fails (#{reason})" do
        before do
          allow(registry).to receive(:manifest_digest).with("library/example-image", "1.1.0").and_raise(error)
        end

        it "falls back to the original candidate" do
          expect(checker.latest_version).to eq("1.1.0.1")
          expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
          expect(checker.updated_requirements.first.source_string("tag")).to eq("1.1.0.1")
        end
      end
    end

    context "when the original candidate lookup fails" do
      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.1.0.1")
                                                    .and_raise(DockerRegistry2::RegistryUnknownException)
      end

      it "preserves the tag-only update and missing-date warning" do
        expect(checker.latest_version).to eq("1.1.0.1")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end

    context "with a failed optional lookup" do
      before do
        allow(registry).to receive(:manifest_digest).with("library/example-image", "1.1.0")
                                                    .and_raise(DockerRegistry2::RegistryUnknownException)
      end

      context "when the original candidate is still in cooldown" do
        let(:candidate_date) { (Time.now - 86_400).iso8601 }

        it "continues searching rather than accepting it unchecked" do
          expect(checker.latest_version).to eq("1.1.0")
          expect(checker.updated_requirements.first.source_string("tag")).to eq("1.1.0")
        end
      end

      context "when the original candidate is a no-op" do
        let(:candidate_digest) { "a" * 64 }

        it "still runs the content check and continues searching" do
          expect(checker.latest_version).to eq("1.1.0")
        end
      end

      context "without cooldown" do
        let(:cooldown) { nil }

        it "also tolerates failure in the optional comparison" do
          expect(checker.latest_version).to eq("1.1.0.1")
        end
      end
    end
  end

  it_behaves_like "optional precision comparison"

  context "with Docker Compose" do
    let(:package_manager) { "docker_compose" }

    it_behaves_like "optional precision comparison"
  end
end
