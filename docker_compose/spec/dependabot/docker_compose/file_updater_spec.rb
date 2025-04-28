# typed: false
# frozen_string_literal: true

require "spec_helper"
require "yaml"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/docker_compose/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::DockerCompose::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ubuntu",
      version: "17.10",
      previous_version: "17.04",
      requirements: [{
        requirement: nil,
        groups: [],
        file: "docker-compose.yml",
        source: { tag: "17.10" }
      }],
      previous_requirements: [{
        requirement: nil,
        groups: [],
        file: "docker-compose.yml",
        source: { tag: "17.04" }
      }],
      package_manager: "docker_compose"
    )
  end
  let(:dockerfile_body) do
    fixture("docker_compose", "composefiles", "multiple")
  end
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      content: dockerfile_body,
      name: "docker-compose.yml"
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

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      expect(updated_files).to all(be_a(Dependabot::DependencyFile))
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated docker-compose.yml" do
      subject(:updated_dockerfile) do
        updated_files.find { |f| f.name == "docker-compose.yml" }
      end

      let(:yaml_content) do
        YAML.safe_load updated_dockerfile.content
      end

      its(:content) { is_expected.to include "image: ubuntu:17.10\n" }
      its(:content) { is_expected.to include "image: python:3.6.3\n" }

      it "contains the expected YAML content" do
        expect(yaml_content).to eq(
          "version" => "2",
          "services" => {
            "interpreter" => { "image" => "python:3.6.3" },
            "os" => { "image" => "ubuntu:17.10" }
          }
        )
      end
    end

    context "when multiple identical lines need to be updated" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "multiple_identical")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "node",
          version: "10.9-alpine",
          previous_version: "10-alpine",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "10.9-alpine" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "10-alpine" }
          }],
          package_manager: "docker_compose"
        )
      end

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) { is_expected.to include "image: node:10.9-alpine\n" }
        its(:content) { is_expected.to include "node-2:" }
      end
    end

    context "when the dependency has a namespace" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "namespace")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "my-fork/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.10" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }],
          package_manager: "docker_compose"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) { is_expected.to include "image: my-fork/ubuntu:17.10\n" }

        its(:content) do
          is_expected.to include "command: [/bin/echo, 'Hello world']"
        end
      end
    end

    context "when the dependency is in a dockerfile_inline" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "inline_dockerfile")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "mariadb",
          version: "11.11.2-jammy",
          previous_version: "10.11.2-jammy",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "11.11.2-jammy" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "10.11.2-jammy" }
          }],
          package_manager: "docker_compose"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) { is_expected.to include "FROM mariadb:11.11.2-jammy" }

        its(:content) do
          is_expected.to include "RUN echo 'Hello'"
        end
      end
    end

    context "when the dependency is from a private registry" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "private_tag")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: {
              registry: "registry-host.io:5000",
              tag: "17.04"
            }
          }],
          package_manager: "docker_compose"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) do
          is_expected
            .to include("image: registry-host.io:5000/myreg/ubuntu:17.10\n")
        end

        its(:content) do
          is_expected.to include "command: [/bin/echo, 'Hello world']"
        end
      end
    end

    context "when the dependency is docker-compose.yml using the v1 API" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "v1_tag")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "myreg/ubuntu",
          version: "17.10",
          previous_version: "17.04",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.10" }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: { tag: "17.04" }
          }],
          package_manager: "docker_compose"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) do
          is_expected
            .to include("image: docker.io/myreg/ubuntu:17.10\n")
        end

        its(:content) do
          is_expected.to include "command: [/bin/echo, 'Hello world']"
        end
      end
    end

    context "when the dependency has a digest" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "digest")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: {
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
            source: {
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                      "dfc38288cf73aa07485005"
            }
          }],
          package_manager: "docker_compose"
        )
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) do
          is_expected.to include "image: ubuntu@sha256:3ea1ca1aa"
        end

        its(:content) do
          is_expected.to include "command: [/bin/echo, 'Hello world']"
        end

        context "when the dockerfile has a tag as well as a digest" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "ubuntu",
              version: "17.10",
              previous_version: "12.04.5",
              requirements: [{
                requirement: nil,
                groups: [],
                file: "docker-compose.yml",
                source: {
                  digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608",
                  tag: "17.10"
                }
              }],
              previous_requirements: [{
                requirement: nil,
                groups: [],
                file: "docker-compose.yml",
                source: {
                  digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                          "dfc38288cf73aa07485005",
                  tag: "12.04.5"
                }
              }],
              package_manager: "docker_compose"
            )
          end

          let(:dockerfile_body) do
            fixture("docker_compose", "composefiles", "digest_and_tag")
          end

          its(:content) do
            is_expected.to include "image: ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end

      context "when the dependency has a private registry" do
        let(:dockerfile_body) do
          fixture("docker_compose", "composefiles", "private_digest")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "myreg/ubuntu",
            version: "17.10",
            previous_version: "17.10",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                registry: "registry-host.io:5000",
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                registry: "registry-host.io:5000",
                digest: "18305429afa14ea462f810146ba44d4363ae76e4c8" \
                        "dfc38288cf73aa07485005"
              }
            }],
            package_manager: "docker_compose"
          )
        end

        its(:length) { is_expected.to eq(1) }

        describe "the updated docker-compose.yml" do
          subject(:updated_dockerfile) do
            updated_files.find { |f| f.name == "docker-compose.yml" }
          end

          its(:content) do
            is_expected.to include("image: registry-host.io:5000/" \
                                   "myreg/ubuntu@sha256:3ea1ca1aa")
          end

          its(:content) do
            is_expected.to include "command: [/bin/echo, 'Hello world']"
          end
        end
      end
    end

    context "when multiple dockerfiles to be updated" do
      let(:files) { [dockerfile, dockefile2] }
      let(:dockefile2) do
        Dependabot::DependencyFile.new(
          name: "custom-name",
          content: dockerfile_body2
        )
      end
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "digest")
      end
      let(:dockerfile_body2) do
        fixture("docker_compose", "composefiles", "digest_and_tag")
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ubuntu",
          version: "17.10",
          previous_version: "12.04.5",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "docker-compose.yml",
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
            file: "docker-compose.yml",
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
          package_manager: "docker_compose"
        )
      end

      describe "the updated docker-compose.yml" do
        subject { updated_files.find { |f| f.name == "docker-compose.yml" } }

        its(:content) do
          is_expected.to include "image: ubuntu@sha256:3ea1ca1aa"
        end
      end

      describe "the updated custom-name file" do
        subject { updated_files.find { |f| f.name == "custom-name" } }

        its(:content) do
          is_expected.to include "image: ubuntu:17.10@sha256:3ea1ca1aa"
        end
      end

      context "when only one needs updating" do
        let(:dockerfile_body) do
          fixture("docker_compose", "composefiles", "bare")
        end

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
            package_manager: "docker_compose"
          )
        end

        describe "the updated custom-name file" do
          subject { updated_files.find { |f| f.name == "custom-name" } }

          its(:content) do
            is_expected.to include "image: ubuntu:17.10@sha256:3ea1ca1aa"
          end
        end
      end

      context "when the image is quoted" do
        let(:dockerfile_body) do
          fixture("docker_compose", "composefiles", "tag_quoted")
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "elastic/elasticsearch",
            version: "8.17.2",
            previous_version: "8.16.4",
            requirements: [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                tag: "8.17.2"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "docker-compose.yml",
              source: {
                tag: "8.16.4"
              }
            }],
            package_manager: "docker_compose"
          )
        end

        describe "the updated custom-name file" do
          subject { updated_files.find { |f| f.name == "docker-compose.yml" } }

          its(:content) do
            is_expected.to include "image: \"elastic/elasticsearch:8.17.2\""
          end
        end
      end
    end

    context "when dependency is default value of variable" do
      let(:dockerfile_body) do
        fixture("docker_compose", "composefiles", "variable")
      end

      describe "the updated docker-compose.yml" do
        subject(:updated_dockerfile) do
          updated_files.find { |f| f.name == "docker-compose.yml" }
        end

        its(:content) { is_expected.to include "image: ${UBUNTU_IMAGE:-ubuntu:17.10}\n" }
      end
    end
  end
end
