# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Docker::MetadataFinder do
  let(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:dependency_without_source) do
    Dependabot::Dependency.new(
      name: "dependabot-fixtures/docker-without-source",
      version: "v0.0.1",
      requirements: [{
        file: "Dockerfile",
        requirement: nil,
        groups: [],
        source: { registry: "ghcr.io", tag: "v0.0.1" }
      }],
      package_manager: "docker"
    )
  end
  let(:dependency_with_source) do
    Dependabot::Dependency.new(
      name: "dependabot-fixtures/docker-with-source",
      version: "v0.0.2",
      requirements: [{
        file: "Dockerfile",
        requirement: nil,
        groups: [],
        source: { registry: "ghcr.io", tag: "v0.0.2" }
      }],
      package_manager: "docker"
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    context "with a docker image that has an OCI source annotation" do
      let(:dependency) { dependency_with_source }

      it "finds the repository" do
        expect(finder.source_url).to eq "https://github.com/dependabot-fixtures/docker-with-source"
      end
    end

    context "with a docker image with both tag and sha that has an OCI source annotation" do
      let(:dependency_with_tag_and_sha_source) do
        Dependabot::Dependency.new(
          name: "dependabot-fixtures/docker-with-source",
          version: "v0.0.2",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { registry: "ghcr.io",
                      digest: "389a5a9a5457ed237b05d623ddc31a42fa97811051dcd02d7ca4ad46bd3edd3e",
                      tag: "v0.0.2" }
          }],
          package_manager: "docker"
        )
      end

      let(:dependency) { dependency_with_tag_and_sha_source }

      it "finds the repository" do
        expect(finder.source_url).to eq "https://github.com/dependabot-fixtures/docker-with-source"
      end
    end

    context "with a digest but no tag or revision data" do
      let(:dependency_with_sha_no_tag) do
        Dependabot::Dependency.new(
          name: "dependabot/dependabot-updater-npm",
          version: "",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { registry: "ghcr.io",
                      digest: "74c21f5886502d754c47a163975062e0d3065e3d19f43c8f48c9dbeb2126767e" }
          }],
          package_manager: "docker"
        )
      end

      let(:dependency) { dependency_with_sha_no_tag }

      it "does not find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "with a docker image that lacks an OCI source annotation" do
      let(:dependency) { dependency_without_source }

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "with a docker image without a tag" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dependabot-fixtures/docker-with-source",
          version: "v0.0.2",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { registry: "ghcr.io",
                      digest: "389a5a9a5457ed237b05d623ddc31a42fa97811051dcd02d7ca4ad46bd3edd3e" }
          }],
          package_manager: "docker"
        )
      end

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "with a docker image without a tag but with org.opencontainers.image.version populated" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "regclient/regctl",
          version: "",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { registry: "ghcr.io",
                      digest: "a734f285c0962e46557bff24489fa0b0521455733f72d9eb30c4f7a5027aeed6" }
          }],
          package_manager: "docker"
        )
      end

      it "finds the repository" do
        expect(finder.source_url).to eq "https://github.com/regclient/regclient"
        # Normally, accessing private methods in tests is discouraged.
        # In this case, we need to verify the branch and commit derived from the image within the source
        # to ensure the source construction logic is correct. This access is for internal validation only.
        # Exposing the source publicly only for this test would be less desirable.
        expect(finder.send(:source).branch).to eq "v0.11.1"
        expect(finder.send(:source).commit).to eq "bf3bcfc47173b49ee8000d1d3a1ac15036e83cf0"
      end
    end

    context "with a docker image without a tag but without a proper tag format or revision" do
      # The image used here has org.opencontainers.image.version set to "24.04"
      # which refers to the Ubuntu version rather than a tag
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "maven",
          version: "",
          requirements: [{
            file: "Dockerfile",
            requirement: nil,
            groups: [],
            source: { registry: "docker.io",
                      digest: "800a33a4cb190082c47abcd57944c852e1dece834f92c0aef65bea6336c52a72" }
          }],
          package_manager: "docker"
        )
      end

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "when an error occurs inspecting the image" do
      let(:dependency) { dependency_with_source }

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command)
          .and_raise("No inspections for you!")
      end

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "when the OCI source annotation isn't a valid url" do
      let(:dependency) { dependency_with_source }

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command)
          .and_return({
            config: {
              Labels: {
                "org.opencontainers.image.source" => "not an url"
              }
            }
          }.to_json)
      end

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end
  end
end
