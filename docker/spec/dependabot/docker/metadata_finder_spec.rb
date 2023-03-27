# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Docker::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
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

  let(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#source_url" do
    context "with a docker image that has an OCI source annotation" do
      let(:dependency) { dependency_with_source }

      it "finds the repository" do
        expect(finder.source_url).to eq "https://github.com/dependabot-fixtures/docker-with-source"
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
                      digest: "sha256:389a5a9a5457ed237b05d623ddc31a42fa97811051dcd02d7ca4ad46bd3edd3e" }
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
        allow(Dependabot::SharedHelpers).
          to receive(:run_shell_command).
          and_raise("No inspections for you!")
      end

      it "doesn't find the repository" do
        expect(finder.source_url).to be_nil
      end
    end

    context "when the OCI source annotation isn't a valid url" do
      let(:dependency) { dependency_with_source }

      before do
        allow(Dependabot::SharedHelpers).
          to receive(:run_shell_command).
          and_return({
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
