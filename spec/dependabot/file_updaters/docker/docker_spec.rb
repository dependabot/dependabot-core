# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/docker/docker"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Docker::Docker do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [dockerfile],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      content: dockerfile_body,
      name: "Dockerfile"
    )
  end
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "multiple") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ubuntu",
      version: "17.10",
      previous_version: "17.04",
      requirements: [
        {
          requirement: nil,
          groups: [],
          file: "Dockerfile",
          source: { type: "tag" }
        }
      ],
      previous_requirements: [
        {
          requirement: nil,
          groups: [],
          file: "Dockerfile",
          source: { type: "tag" }
        }
      ],
      package_manager: "docker"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated Dockerfile" do
      subject(:updated_dockerfile) do
        updated_files.find { |f| f.name == "Dockerfile" }
      end

      its(:content) { is_expected.to include "FROM ubuntu:17.10\n" }
      its(:content) { is_expected.to include "FROM python:3.6.3\n" }
      its(:content) { is_expected.to include "RUN apt-get update" }
    end

    context "when the dependency has a namespace" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "namespace") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "my_fork/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag" }
            }
          ],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag" }
            }
          ],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM my_fork/ubuntu:17.10\n" }
        its(:content) { is_expected.to include "RUN apt-get update" }
      end
    end

    context "when the dependency has a digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "digest") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "digest" }
            }
          ],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "digest" }
            }
          ],
          package_manager: "docker"
        )
      end

      before do
        registry_url = "https://registry.hub.docker.com/v2/"
        stub_request(:get, registry_url).and_return(status: 200)

        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        ubuntu_url = "https://registry.hub.docker.com/v2/library/ubuntu/"
        old_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_12.04.5.json")
        stub_request(:head, ubuntu_url + "manifests/12.04.5").
          and_return(status: 200, body: "", headers: JSON.parse(old_headers))

        new_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
        stub_request(:head, ubuntu_url + "manifests/17.10").
          and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM ubuntu@sha256:3ea1ca1aa" }
        its(:content) { is_expected.to include "RUN apt-get update" }
      end
    end
  end
end
