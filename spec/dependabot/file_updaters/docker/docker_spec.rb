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
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
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
          name: "my-fork/ubuntu",
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

        its(:content) { is_expected.to include "FROM my-fork/ubuntu:17.10\n" }
        its(:content) { is_expected.to include "RUN apt-get update" }
      end
    end

    context "when the dependency is from a private registry" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "private_tag") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag", registry: "registry-host.io:5000" }
            }
          ],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag", registry: "registry-host.io:5000" }
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

        its(:content) do
          is_expected.
            to include("FROM registry-host.io:5000/myreg/ubuntu:17.10\n")
        end
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

      let(:repo_url) { "https://registry.hub.docker.com/v2/library/ubuntu/" }

      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        old_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_12.04.5.json")
        stub_request(:head, repo_url + "manifests/12.04.5").
          and_return(status: 200, body: "", headers: JSON.parse(old_headers))

        new_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
        stub_request(:head, repo_url + "manifests/17.10").
          and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      its(:length) { is_expected.to eq(1) }

      context "when the docker registry times out" do
        before do
          old_headers = fixture(
            "docker",
            "registry_manifest_headers",
            "ubuntu_12.04.5.json"
          )
          stub_request(:head, repo_url + "manifests/12.04.5").
            to_raise(RestClient::Exceptions::OpenTimeout).then.
            to_return(status: 200, body: "", headers: JSON.parse(old_headers))
        end

        its(:length) { is_expected.to eq(1) }

        context "every time" do
          before do
            stub_request(:head, repo_url + "manifests/12.04.5").
              to_raise(RestClient::Exceptions::OpenTimeout)
          end

          it "raises" do
            expect { updater.updated_dependency_files }.
              to raise_error(RestClient::Exceptions::OpenTimeout)
          end
        end
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM ubuntu@sha256:3ea1ca1aa" }
        its(:content) { is_expected.to include "RUN apt-get update" }

        context "when the dockerfile has a tag as well as a digest" do
          let(:dockerfile_body) do
            fixture("docker", "dockerfiles", "digest_and_tag")
          end

          its(:content) do
            is_expected.to include "FROM ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end

      context "when the dependency has a private registry" do
        let(:dockerfile_body) do
          fixture("docker", "dockerfiles", "private_digest")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "myreg/ubuntu",
            version: "17.10",
            previous_version: "12.04.5",
            requirements: [
              {
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: { type: "digest", registry: "registry-host.io:5000" }
              }
            ],
            previous_requirements: [
              {
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: { type: "digest", registry: "registry-host.io:5000" }
              }
            ],
            package_manager: "docker"
          )
        end
        let(:repo_url) { "https://registry-host.io:5000/v2/myreg/ubuntu/" }

        context "without authentication credentials" do
          it "raises a to Dependabot::PrivateSourceNotReachable error" do
            expect { updated_files }.
              to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
                expect(error.source).to eq("registry-host.io:5000")
              end
          end
        end

        context "with authentication credentials" do
          let(:credentials) do
            [
              {
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "registry" => "registry-host.io:5000",
                "username" => "grey",
                "password" => "pa55word"
              }
            ]
          end

          its(:length) { is_expected.to eq(1) }

          describe "the updated Dockerfile" do
            subject(:updated_dockerfile) do
              updated_files.find { |f| f.name == "Dockerfile" }
            end

            its(:content) do
              is_expected.to include("FROM registry-host.io:5000/"\
                                     "myreg/ubuntu@sha256:3ea1ca1aa")
            end
            its(:content) { is_expected.to include "RUN apt-get update" }
          end
        end
      end
    end
  end
end
