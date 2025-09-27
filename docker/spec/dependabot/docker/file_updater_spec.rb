# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Docker::FileUpdater do
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
  let(:helmfile_body) { fixture("helm", "yaml", "values.yaml") }
  let(:helmfile) do
    Dependabot::DependencyFile.new(
      content: helmfile_body,
      name: "values.yaml"
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
  let(:helm_files) { [helmfile] }
  let(:helm_updater) do
    described_class.new(
      dependency_files: helm_files,
      dependencies: [helm_dependency],
      credentials: credentials
    )
  end
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
  let(:podfile_body) { fixture("kubernetes", "yaml", "multiple.yaml") }
  let(:podfile) do
    Dependabot::DependencyFile.new(
      content: podfile_body,
      name: "multiple.yaml"
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
  let(:yaml_files) { [podfile] }
  let(:yaml_updater) do
    described_class.new(
      dependency_files: yaml_files,
      dependencies: [yaml_dependency],
      credentials: credentials
    )
  end
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
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "multiple") }
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      content: dockerfile_body,
      name: "Dockerfile"
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
  let(:files) { [dockerfile] }
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  describe "#updated_files_regex" do
    subject(:updated_files_regex) { described_class.updated_files_regex }

    it "is not empty" do
      expect(updated_files_regex).not_to be_empty
    end

    context "when files match the regex patterns" do
      it "returns true for files that should be updated" do
        matching_files = [
          "Dockerfile",
          "dockerfile",
          "my_dockerfile",
          "myapp.yaml",
          "config.yml",
          "service.yaml",
          "v1_tag.yaml",
          ".env",
          ".env.local",
          "app.env",
          "production.env"
        ]

        matching_files.each do |file_name|
          expect(updated_files_regex).to(be_any { |regex| file_name.match?(regex) })
        end
      end

      it "returns false for files that should not be updated" do
        non_matching_files = [
          "README.md",
          ".github/workflow/main.yml",
          "some_random_file.rb",
          "requirements.txt",
          "package-lock.json",
          "package.json"
        ]

        non_matching_files.each do |file_name|
          expect(updated_files_regex).not_to(be_any { |regex| file_name.match?(regex) })
        end
      end
    end
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
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "10.9.4-alpine" }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "10.9.4-alpine" }
            }
          ],
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

    context "when multiple identical named dependencies with same tag, but different variants with digests" do
      let(:dockerfile_body) do
        fixture("docker", "dockerfiles", "multi_stage_different_variants_with_digests")
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
            source: {
              tag: "3.10.6",
              digest: "8d1f943ceaaf3b3ce05df5c0926e7958836b048b70" \
                      "0176bf9c56d8f37ac13fca"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              tag: "3.10.6-slim",
              digest: "c8ef926b002a8371fff6b4f40142dcc6d6f7e217f7" \
                      "afce2c2d1ed2e6c28e2b7c"
            }
          }],
          previous_requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                tag: "3.10.5",
                digest: "bdf0079de4094afdb26b94d9f89b716499436282c9" \
                        "72461d945a87899c015c23"
              }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                tag: "3.10.5-slim",
                digest: "bdf0079de4094afdb26b94d9f89b716499436282c9" \
                        "72461d945a87899c015c23"
              }
            }
          ],
          package_manager: "docker"
        )
      end

      describe "the updated Dockerfile" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "Dockerfile" }
        end

        its(:content) do
          is_expected.to include "FROM python:3.10.6@sha256:8d1f943ceaaf3b3ce05df5c0926e7958836b048b" \
                                 "700176bf9c56d8f37ac13fca AS base\n"
        end

        its(:content) do
          is_expected.to include "FROM python:3.10.6-slim@sha256:c8ef926b002a8371fff6b4f40142dcc6d6f" \
                                 "7e217f7afce2c2d1ed2e6c28e2b7c AS production\n"
        end

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
          is_expected
            .to include("FROM registry-host.io:5000/myreg/ubuntu:17.10\n")
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
          is_expected
            .to include("FROM docker.io/myreg/ubuntu:17.10\n")
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
              # corresponds to the tag "17.10"
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              # corresponds to the tag "12.04.5"
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
                  tag: "17.10",
                  digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608"
                }
              }],
              previous_requirements: [{
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: {
                  tag: "12.04.5",
                  digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                          "dfc38288cf73aa07485005"
                }
              }],
              package_manager: "docker"
            )
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
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                registry: "registry-host.io:5000",
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
            is_expected.to include(
              "FROM registry-host.io:5000/" \
              "myreg/ubuntu@sha256:3ea1ca1aa"
            )
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
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608",
                tag: "17.10"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "custom-name",
              source: {
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005",
                tag: "12.04.5"
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
          is_expected
            .to include("    image: registry-host.io:5000/myreg/ubuntu:17.10\n")
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
          is_expected
            .to include("    image: docker.io/myreg/ubuntu:17.10\n")
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
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
          subject(:updated_podfile) do
            updated_files.find { |f| f.name == "digest_and_tag.yaml" }
          end

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
                  digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608"
                }
              }],
              previous_requirements: [{
                requirement: nil,
                groups: [],
                file: "digest_and_tag.yaml",
                source: {
                  tag: "12.04.5",
                  digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                          "dfc38288cf73aa07485005"
                }
              }],
              package_manager: "docker"
            )
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
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "private_digest.yaml",
              source: {
                registry: "registry-host.io:5000",
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
            is_expected.to include(
              "image: registry-host.io:5000/" \
              "myreg/ubuntu@sha256:3ea1ca1aa"
            )
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
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "digest_and_tag.yaml",
            source: {
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "digest.yaml",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "digest_and_tag.yaml",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "digest_and_tag.yaml",
              source: {
                tag: "12.04.5",
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
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

    context "when a digest is used" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "digest.yaml") }
      let(:helm_dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "sha256:c9cf959fd83770dfdefd8fb42cfef0761432af36a764c077aed54bbc5bb25368",
          previous_version: "sha256:295c7be079025306c4f1d65997fcf7adb411c88f139ad1d34b537164aa060369",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "sha256:c9cf959fd83770dfdefd8fb42cfef0761432af36a764c077aed54bbc5bb25368" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "values.yaml",
            source: { tag: "sha256:295c7be079025306c4f1d65997fcf7adb411c88f139ad1d34b537164aa060369" }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) do
          is_expected.to include "version: 'sha256:c9cf959fd83770dfdefd8fb42cfef0761432af36a7"
        end
      end
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

    context "when there are mixed helm and docker image formats and we update the docker format" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
        )
      end
      let(:helmfile_body) { fixture("helm", "yaml", "mixed-image.yaml") }
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

        its(:content) { is_expected.to include "  image: nginx:1.14.3\n" }
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

    context "with version number" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          content: helmfile_body,
          name: "values.yaml"
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

      its(:length) { is_expected.to eq(1) }

      describe "the updated helmfile" do
        subject(:updated_helmfile) do
          updated_files.find { |f| f.name == "values.yaml" }
        end

        its(:content) { is_expected.to include "image:\n  repository: 'nginx'\n  tag: 1.14.3\n" }
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

  describe "#updated_dependency_files with .env files" do
    subject(:updated_files) { env_updater.updated_dependency_files }

    let(:env_dependency) do
      Dependabot::Dependency.new(
        name: "nginx",
        version: "1.22.0",
        previous_version: "1.21.0",
        requirements: [{
          requirement: nil,
          groups: [],
          file: ".env",
          source: {
            tag: "1.22.0",
            digest: "new123abc456def789012345678901234567890123456789012345678901234abcd"
          }
        }],
        previous_requirements: [{
          requirement: nil,
          groups: [],
          file: ".env",
          source: {
            tag: "1.21.0",
            digest: "0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804"
          }
        }],
        package_manager: "docker"
      )
    end
    let(:envfile_body) { fixture("env", "basic.env") }
    let(:envfile) do
      Dependabot::DependencyFile.new(
        content: envfile_body,
        name: ".env"
      )
    end
    let(:env_files) { [envfile] }
    let(:env_updater) do
      described_class.new(
        dependency_files: env_files,
        dependencies: [env_dependency],
        credentials: credentials
      )
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated .env file" do
      subject(:updated_envfile) do
        updated_files.find { |f| f.name == ".env" }
      end

      its(:content) do
        is_expected.to include "NGINX_IMAGE_TAG=nginx:1.22.0@sha256:" \
                               "new123abc456def789012345678901234567890123456789012345678901234abcd"
      end

      its(:content) do
        is_expected.to include "REDIS_IMAGE_TAG=redis:6.2.5@sha256:" \
                               "4c854aa03f6b7e9bb2b945e8e2a17f565266a103c70bb3275b57e4f81a7e92a0"
      end

      its(:content) { is_expected.to include "# Container Image Tags" }
    end

    context "with tag-only updates" do
      let(:envfile_body) { fixture("env", "tag_only.env") }
      let(:env_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.22.0",
          previous_version: "1.21.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: { tag: "1.22.0" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: { tag: "1.21.0" }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated .env file" do
        subject(:updated_envfile) do
          updated_files.find { |f| f.name == ".env" }
        end

        its(:content) { is_expected.to include "API_IMAGE=nginx:1.22.0" }
        its(:content) { is_expected.to include "DB_IMAGE=postgres:13.4" }
        its(:content) { is_expected.to include "CACHE_IMAGE=redis:6.2.5" }
      end
    end

    context "with namespace images" do
      let(:envfile_body) { fixture("env", "namespace.env") }
      let(:env_dependency) do
        Dependabot::Dependency.new(
          name: "namespace/app",
          version: "new456def789abc012345678901234567890123456789012345678901234567890",
          previous_version: "abc123def456789012345678901234567890123456789012345678901234abcd",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              registry: "my-registry.io",
              tag: "v1.0.0",
              digest: "new456def789abc012345678901234567890123456789012345678901234567890"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              registry: "my-registry.io",
              tag: "v1.0.0",
              digest: "abc123def456789012345678901234567890123456789012345678901234abcd"
            }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated .env file" do
        subject(:updated_envfile) do
          updated_files.find { |f| f.name == ".env" }
        end

        its(:content) do
          is_expected.to include "APP_IMAGE=my-registry.io/namespace/app:v1.0.0@sha256:" \
                                 "new456def789abc012345678901234567890123456789012345678901234567890"
        end

        its(:content) do
          is_expected.to include "WORKER_IMAGE=registry.example.com/team/worker:latest@sha256:" \
                                 "def456abc789012345678901234567890123456789012345678901234567890e"
        end
      end
    end

    context "with mixed content" do
      let(:envfile_body) { fixture("env", "mixed.env") }
      let(:env_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.22.0",
          previous_version: "1.21.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              tag: "1.22.0",
              digest: "updated64dd661dcadfd9958f9e0de192a1fdda2c162a35668ab6ac42b465f0860"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              tag: "1.21.0",
              digest: "9522864dd661dcadfd9958f9e0de192a1fdda2c162a35668ab6ac42b465f0860"
            }
          }],
          package_manager: "docker"
        )
      end

      describe "the updated .env file" do
        subject(:updated_envfile) do
          updated_files.find { |f| f.name == ".env" }
        end

        its(:content) do
          is_expected.to include "NGINX_IMAGE=nginx:1.22.0@sha256:" \
                                 "updated64dd661dcadfd9958f9e0de192a1fdda2c162a35668ab6ac42b465f0860"
        end

        its(:content) { is_expected.to include "REDIS_IMAGE=redis:6.2.5" }
        its(:content) { is_expected.to include "DATABASE_URL=postgresql://user:pass@localhost:5432/mydb" }
        its(:content) { is_expected.to include "DEBUG=true" }
      end
    end

    context "with multiple .env files" do
      let(:env_files) { [envfile, envfile2] }
      let(:envfile2) do
        Dependabot::DependencyFile.new(
          name: "app.env",
          content: envfile_body2
        )
      end
      let(:envfile_body) { fixture("env", "basic.env") }
      let(:envfile_body2) { fixture("env", "tag_only.env") }
      let(:env_dependency) do
        Dependabot::Dependency.new(
          name: "nginx",
          version: "1.22.0",
          previous_version: "1.21.0",
          requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              tag: "1.22.0",
              digest: "new123abc456def789012345678901234567890123456789012345678901234abcd"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: ".env",
            source: {
              tag: "1.21.0",
              digest: "0b01b93c3a93e747fba8d9bb1025011bf108d77c9cf8252f17a6f3d63a1b5804"
            }
          }],
          package_manager: "docker"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated .env file" do
        subject(:updated_envfile) do
          updated_files.find { |f| f.name == ".env" }
        end

        its(:content) do
          is_expected.to include "NGINX_IMAGE_TAG=nginx:1.22.0@sha256:" \
                                 "new123abc456def789012345678901234567890123456789012345678901234abcd"
        end
      end

      context "when only the second file needs updating" do
        let(:env_dependency) do
          Dependabot::Dependency.new(
            name: "nginx",
            version: "1.22.0",
            previous_version: "1.21.0",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "app.env",
              source: { tag: "1.22.0" }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "app.env",
              source: { tag: "1.21.0" }
            }],
            package_manager: "docker"
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated app.env file" do
          subject(:updated_envfile) do
            updated_files.find { |f| f.name == "app.env" }
          end

          its(:content) { is_expected.to include "API_IMAGE=nginx:1.22.0" }
          its(:content) { is_expected.to include "DB_IMAGE=postgres:13.4" }
        end
      end
    end
  end
end
