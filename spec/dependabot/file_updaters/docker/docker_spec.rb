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
              source: {
                type: "digest",
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                        "ca97eba880ebf600d68608"
              }
            }
          ],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                type: "digest",
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
                        "dfc38288cf73aa07485005"
              }
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
                source: {
                  type: "digest",
                  registry: "registry-host.io:5000",
                  digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                          "ca97eba880ebf600d68608"
                }
              }
            ],
            previous_requirements: [
              {
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: {
                  type: "digest",
                  registry: "registry-host.io:5000",
                  digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
                          "dfc38288cf73aa07485005"
                }
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
            is_expected.to include("FROM registry-host.io:5000/"\
                                   "myreg/ubuntu@sha256:3ea1ca1aa")
          end
          its(:content) { is_expected.to include "RUN apt-get update" }
        end
      end
    end
  end
end
