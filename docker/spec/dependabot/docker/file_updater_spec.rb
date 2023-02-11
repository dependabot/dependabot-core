# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Docker::FileUpdater do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  let(:files) { [dockerfile] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
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
      requirements: [{
        requirement: nil,
        groups: [],
        file: "Dockerfile",
        source: { tag: "17.10" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "Dockerfile",
        source: { tag: "17.04" }
      }],
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

    context "when multiple identical lines need to be updated" do
      let(:dockerfile_body) do
        fixture("docker", "dockerfiles", "multiple_identical")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "10.9-alpine",
          previous_version: "10-alpine",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "10.9-alpine" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "10-alpine" }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM node:10.9-alpine AS" }
        its(:content) { is_expected.to include "FROM node:10.9-alpine\n" }
        its(:content) { is_expected.to include "RUN apk add" }
      end
    end

    context "when multiple identical named dependencies with different tags" do
      let(:dockerfile_body) do
        fixture("docker", "dockerfiles", "multi_stage_different_tags")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "10.9.4-alpine",
          previous_version: "10.9.2-alpine",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "10.9.4-alpine" }
          }],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "10.9.2-alpine" }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "10.9.3-alpine" }
            }
          ],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM node:10.9.4-alpine AS" }
        its(:content) { is_expected.to include "FROM node:10.9.4-alpine\n" }
        its(:content) { is_expected.to include "RUN apk add" }
      end
    end

    context "when multiple identical named dependencies with same tag, but different variants" do
      let(:dockerfile_body) do
        fixture("docker", "dockerfiles", "multi_stage_different_variants")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "python",
          version: "3.10.6",
          previous_version: "3.10.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "3.10.6" }
          }, {
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "3.10.6-slim" }
          }],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "3.10.5" }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "3.10.5-slim" }
            }
          ],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) { is_expected.to include "FROM python:3.10.6 AS base\n" }
        its(:content) { is_expected.to include "FROM python:3.10.6-slim AS production\n" }
        its(:content) { is_expected.to include "ENV PIP_NO_CACHE_DIR=off \\\n" }
      end
    end

    context "when the dependency has a namespace" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "namespace") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "my-fork/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "17.10" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "17.04" }
          }],
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
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.04"
            }
          }],
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

    context "when the dependency is Dockerfile using the v1 API" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "v1_tag") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "17.10" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "17.04" }
          }],
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
            to include("FROM docker.io/myreg/ubuntu:17.10\n")
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
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }],
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
            previous_version: "17.10",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                registry: "registry-host.io:5000",
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                registry: "registry-host.io:5000",
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005"
              }
            }],
            package_manager: "docker"
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated Dockerfile" do
          subject(:updated_dockerfile) do
            updated_files.find { |f| f.name == "Dockerfile" }
          end

          its(:content) do
            is_expected.to include("FROM registry-host.io:5000/" \
                                   "myreg/ubuntu@sha256:3ea1ca1aa")
          end
          its(:content) { is_expected.to include "RUN apt-get update" }
        end
      end
    end

    context "when multiple dockerfiles to be updated" do
      let(:files) { [dockerfile, dockerfile2] }
      let(:dockerfile2) do
        Dependabot::DependencyFile.new(
          name: "custom-name",
          content: dockerfile_body2
        )
      end
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "digest") }
      let(:dockerfile_body2) do
        fixture("docker", "dockerfiles", "digest_and_tag")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005",
              tag: "12.04.5"
            }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject { updated_files.find { |f| f.name == "Dockerfile" } }
        its(:content) { is_expected.to include "FROM ubuntu@sha256:3ea1ca1aa" }
      end

      describe "the updated custom-name file" do
        subject { updated_files.find { |f| f.name == "custom-name" } }

        its(:content) do
          is_expected.to include "FROM ubuntu:17.10@sha256:3ea1ca1aa"
        end
      end

      context "when only one needs updating" do
        let(:dockerfile_body) { fixture("docker", "dockerfiles", "bare") }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "ubuntu",
            version: "17.10",
            previous_version: "12.04.5",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "custom-name",
              source: {
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "custom-name",
              source: {
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005"
              }
            }],
            package_manager: "docker"
          )
        end

        describe "the updated custom-name file" do
          subject { updated_files.find { |f| f.name == "custom-name" } }

          its(:content) do
            is_expected.to include "FROM ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end
    end

    context "when dockerfile includes platform" do
      let(:dockerfile_body) do
        fixture("docker", "dockerfiles", "platform")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "10.9-alpine",
          previous_version: "10-alpine",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "10.9-alpine" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "10-alpine" }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) do
          is_expected.to include "FROM --platform=$BUILDPLATFORM " \
                                 "node:10.9-alpine AS"
        end
        its(:content) { is_expected.to include "FROM node:10.9-alpine\n" }
        its(:content) { is_expected.to include "RUN apk add" }
      end
    end
  end

  let(:yaml_updater) do
    described_class.new(
      dependency_files: yaml_files,
      dependencies: [yaml_dependency],
      credentials: credentials
    )
  end
  let(:yaml_files) { [podfile] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:podfile) do
    Dependabot::DependencyFile.new(
      content: podfile_body,
      name: "multiple.yaml"
    )
  end
  let(:podfile_body) { fixture("kubernetes", "yaml", "multiple.yaml") }
  let(:yaml_dependency) do
    Dependabot::Dependency.new(
      name: "ubuntu",
      version: "17.10",
      previous_version: "17.04",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "multiple.yaml",
        source: { tag: "17.10" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "multiple.yaml",
        source: { tag: "17.04" }
      }],
      package_manager: "docker"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { yaml_updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated podfile" do
      subject(:updated_podfile) do
        updated_files.find { |f| f.name == "multiple.yaml" }
      end

      its(:content) { is_expected.to include "image: ubuntu:17.10\n" }
      its(:content) { is_expected.to include "image: nginx:1.14.2\n" }
      its(:content) { is_expected.to include "kind: Pod" }
    end

    context "when the image contains a hyphen" do
      let(:podfile_body) { fixture("kubernetes", "yaml", "hyphen.yaml") }
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "hyphen.yaml"
        )
      end
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "hyphen.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "hyphen.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "hyphen.yaml" }
        end

        its(:content) { is_expected.to include "  - image: nginx:1.14.3\n    name: nginx" }
        its(:content) { is_expected.to include "kind: Pod" }
      end
    end

    context "when multiple identical lines need to be updated" do
      let(:podfile_body) do
        fixture("kubernetes", "yaml", "multiple_identical.yaml")
      end
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "multiple_identical.yaml"
        )
      end
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "multiple_identical.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "multiple_identical.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "multiple_identical.yaml" }
        end

        its(:content) { is_expected.to include "  - name: nginx2\n    image: nginx:1.14.3" }
        its(:content) { is_expected.to include "  - name: nginx\n    image: nginx:1.14.3" }
        its(:content) { is_expected.to include "kind: Pod" }
      end
    end

    context "when the dependency has a namespace" do
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "namespace.yaml"
        )
      end
      let(:podfile_body) { fixture("kubernetes", "yaml", "namespace.yaml") }
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "my-repo/nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "namespace.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "namespace.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "namespace.yaml" }
        end

        its(:content) { is_expected.to include "    image: my-repo/nginx:1.14.3\n" }
        its(:content) { is_expected.to include "kind: Pod\n" }
      end
    end

    context "when the dependency is from a private registry" do
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "private_tag.yaml"
        )
      end
      let(:podfile_body) { fixture("kubernetes", "yaml", "private_tag.yaml") }
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "private_tag.yaml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "private_tag.yaml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.04"
            }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "private_tag.yaml" }
        end

        its(:content) do
          is_expected.
            to include("    image: registry-host.io:5000/myreg/ubuntu:17.10\n")
        end
        its(:content) { is_expected.to include "kind: Pod" }
      end
    end

    context "when the dependency is podfile using the v1 API" do
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "v1_tag.yaml"
        )
      end
      let(:podfile_body) { fixture("kubernetes", "yaml", "v1_tag.yaml") }
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "v1_tag.yaml",
            source: {
              registry: "docker.io",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "v1_tag.yaml",
            source: {
              registry: "docker.io",
              tag: "17.04"
            }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "v1_tag.yaml" }
        end

        its(:content) do
          is_expected.
            to include("    image: docker.io/myreg/ubuntu:17.10\n")
        end
        its(:content) { is_expected.to include "kind: Pod" }
      end
    end

    context "when the dependency has a digest" do
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "digest.yaml"
        )
      end
      let(:podfile_body) { fixture("kubernetes", "yaml", "digest.yaml") }
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated podfile" do
        subject(:updated_podfile) do
          updated_files.find { |f| f.name == "digest.yaml" }
        end

        its(:content) { is_expected.to include "    image: ubuntu@sha256:3ea1ca1aa" }
        its(:content) { is_expected.to include "kind: Pod" }

        context "when the podfile has a tag as well as a digest" do
          let(:podfile) do
            Dependabot::DependencyFile.new(
              content: podfile_body,
              name: "digest_and_tag.yaml"
            )
          end
          let(:podfile_body) do
            fixture("kubernetes", "yaml", "digest_and_tag.yaml")
          end
          let(:yaml_dependency) do
            Dependabot::Dependency.new(
              name: "ubuntu",
              version: "17.10",
              previous_version: "12.04.5",
              requirements: [{
                requirement: nil,
                groups: [],
                file: "digest_and_tag.yaml",
                source: {
                  tag: "17.10",
                  digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608"
                }
              }],
              previous_requirements: [{
                requirement: nil,
                groups: [],
                file: "digest_and_tag.yaml",
                source: {
                  tag: "12.04.5",
                  digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                          "dfc38288cf73aa07485005"
                }
              }],
              package_manager: "docker"
            )
          end

          subject(:updated_podfile) do
            updated_files.find { |f| f.name == "digest_and_tag.yaml" }
          end

          its(:content) do
            is_expected.to include "    image: ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end

      context "when the dependency has a private registry" do
        let(:podfile) do
          Dependabot::DependencyFile.new(
            content: podfile_body,
            name: "private_digest.yaml"
          )
        end
        let(:podfile_body) do
          fixture("kubernetes", "yaml", "private_digest.yaml")
        end
        let(:yaml_dependency) do
          Dependabot::Dependency.new(
            name: "myreg/ubuntu",
            version: "17.10",
            previous_version: "17.10",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "private_digest.yaml",
              source: {
                registry: "registry-host.io:5000",
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "private_digest.yaml",
              source: {
                registry: "registry-host.io:5000",
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005"
              }
            }],
            package_manager: "docker"
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated podfile" do
          subject(:updated_podfile) do
            updated_files.find { |f| f.name == "private_digest.yaml" }
          end

          its(:content) do
            is_expected.to include("image: registry-host.io:5000/" \
                                   "myreg/ubuntu@sha256:3ea1ca1aa")
          end
          its(:content) { is_expected.to include "kind: Pod" }
        end
      end
    end

    context "when multiple yaml to be updated" do
      let(:yaml_files) { [podfile, podfile2] }
      let(:podfile2) do
        Dependabot::DependencyFile.new(
          name: "digest_and_tag.yaml",
          content: podfile_body2
        )
      end
      let(:podfile) do
        Dependabot::DependencyFile.new(
          content: podfile_body,
          name: "digest.yaml"
        )
      end
      let(:podfile_body) { fixture("kubernetes", "yaml", "digest.yaml") }
      let(:podfile_body2) do
        fixture("kubernetes", "yaml", "digest_and_tag.yaml")
      end
      let(:yaml_dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "digest_and_tag.yaml",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "digest_and_tag.yaml",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005",
              tag: "12.04.5"
            }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated podfile" do
        subject { updated_files.find { |f| f.name == "digest.yaml" } }
        its(:content) { is_expected.to include "image: ubuntu@sha256:3ea1ca1aa" }
      end

      describe "the updated custom-name file" do
        subject { updated_files.find { |f| f.name == "digest_and_tag.yaml" } }

        its(:content) do
          is_expected.to include "image: ubuntu:17.10@sha256:3ea1ca1aa"
        end
      end

      context "when only one needs updating" do
        let(:podfile_body) { fixture("kubernetes", "yaml", "bare.yaml") }

        let(:yaml_dependency) do
          Dependabot::Dependency.new(
            name: "ubuntu",
            version: "17.10",
            previous_version: "12.04.5",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "digest_and_tag.yaml",
              source: {
                tag: "17.10",
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "digest_and_tag.yaml",
              source: {
                tag: "12.04.5",
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005"
              }
            }],
            package_manager: "docker"
          )
        end

        describe "the updated custom-name file" do
          subject { updated_files.find { |f| f.name == "digest_and_tag.yaml" } }

          its(:content) do
            is_expected.to include "image: ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end
    end
  end
  let(:helm_updater) do
    described_class.new(
      dependency_files: helm_files,
      dependencies: [helm_dependency],
      credentials: credentials
    )
  end
  let(:helm_files) { [helmfile] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:helmfile) do
    Dependabot::DependencyFile.new(
      content: helmfile_body,
      name: "values.yaml" # TODO not sure if I need to replace the filenames here or if I can override later in a specific test
    )
  end
  let(:helmfile_body) { fixture("helm", "yaml", "values.yaml") }
  let(:helm_dependency) do
    Dependabot::Dependency.new(
      name: "nginx",
      version: "1.14.3",
      previous_version: "1.14.2",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "values.yaml",
        source: { tag: "1.14.3" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "values.yaml",
        source: { tag: "1.14.2" }
      }],
      package_manager: "docker"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { helm_updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated podfile" do
      subject(:updated_helmfile) do
        updated_files.find { |f| f.name == "values.yaml" }
      end

      its(:content) { is_expected.to include "image:\n  repository: 'nginx'\n  tag: 1.14.3\n" }
    end

    context "when there are multiple images" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "multi-image.yaml") }
      let(:helm_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) { is_expected.to include "  image:\n    repository: 'nginx'\n    tag: 1.14.3\n" }
        its(:content) { is_expected.to include "  image:\n    repository: 'canonical/ubuntu'\n    tag: 18.04" }
      end
    end

    context "when version has double quotes" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "double-quotes.yaml") }
      let(:helm_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) { is_expected.to include "image:\n  repository: \"nginx\"\n  tag: \"1.14.3\"\n" }
      end
    end

    context "when version has single quotes" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "single-quotes.yaml") }
      let(:helm_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.14.3",
          previous_version: "1.14.2",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.3" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "1.14.2" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) { is_expected.to include "image:\n  repository: 'nginx'\n  tag: '1.14.3'\n" }
      end
    end

    context "when alternate version format" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "no-registry.yaml") }
      let(:helm_dependency) do
        Dependabot::Dependency.new(
          name: "sql/sql",
          version: "v1.2.4",
          previous_version: "v1.2.3",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "v1.2.4" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "v1.2.3" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) { is_expected.to include "image:\n  repository: 'mcr.microsoft.com/sql/sql'\n  version: v1.2.4" }
      end
    end
  end
end
