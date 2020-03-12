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
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                      "ca97eba880ebf600d68608"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
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
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                registry: "registry-host.io:5000",
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
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
            is_expected.to include("FROM registry-host.io:5000/"\
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
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                      "ca97eba880ebf600d68608"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                      "ca97eba880ebf600d68608",
              tag: "17.10"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
                      "dfc38288cf73aa07485005"
            }
          }, {
            requirement: nil,
            groups: [],
            file: "custom-name",
            source: {
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
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
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                        "ca97eba880ebf600d68608"
              }
            }],
            previous_requirements: [{
              requirement: nil,
              groups: [],
              file: "custom-name",
              source: {
                digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8"\
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
    describe "#updated_dependency_files", :pix4d do
      it_behaves_like "a dependency file updater"

      it "raises the correct error when 'dependency_files' do not contain \
         any files or when 'dependency_files' is not a list" do
        expect do
          described_class.new(
            dependencies: nil,
            dependency_files: [nil],
            credentials: nil
          )
        end .to raise_error("No file!")

        expect do
          described_class.new(
            dependencies: nil,
            dependency_files: nil,
            credentials: nil
          )
        end .to raise_error("undefined method `any?' for nil:NilClass")
      end

      it "updates the input files" do
        # expected output
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "public-simple.yml",
            source: { tag: "1.10" }
          }]

        previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "public-simple.yml",
            source: { tag: "1.0.7" }
          }]

        # required input for the FileUpdater class
        input_files = Dependabot::DependencyFile.new(
          name: "public-simple.yml",
          content: fixture("pipelines", "public-simple.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "public-image-name-1",
          version: "1.10",
          previous_version: "1.0.7",
          requirements: expected_requirements,
          previous_requirements: previous_requirements,
          package_manager: "docker"
        )

        # call and instance to the FileUpdater class
        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("public-simple.yml")
        expect(updated_files.first.content).to include "public-image-name-1\n"
        expect(updated_files.first.content).to include "tag: 1.10\n"
      end

      it "correctly updates the input files if we use the same number/string
        in both the repository and tag" do
        # expected output
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "private-complex.yml",
            source: { tag: "20190825" }
          }]

        previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "private-complex.yml",
            source: { tag: "0" }
          }]

        # required input for the FileUpdater class
        input_files = Dependabot::DependencyFile.new(
          name: "private-complex.yml",
          content: fixture("pipelines", "private-complex.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "private.repo.com/private-image-name-16.04",
          version: "20190825",
          previous_version: 0,
          requirements: expected_requirements,
          previous_requirements: previous_requirements,
          package_manager: "docker"
        )

        # call and instance to the FileUpdater class
        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("private-complex.yml")
        expect(
          updated_files.first.content
        ).to include "private-image-name-16.04\n"
        expect(updated_files.first.content).to include "tag: 20190825\n"
      end

      it "correctly updates the input files if we use the same number/string
        in both the repository and tag (new tag format)" do
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "private-complex.yml",
            source: { tag: "20190825090000" }
          }]

        expected_previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "private-complex.yml",
            source: { tag: "0" }
          }]

        input_files = Dependabot::DependencyFile.new(
          name: "private-complex.yml",
          content: fixture("pipelines", "private-complex.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "private.repo.com/private-image-name-16.04",
          version: "20190825090000",
          previous_version: 0,
          requirements: expected_requirements,
          previous_requirements: expected_previous_requirements,
          package_manager: "docker"
        )

        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("private-complex.yml")
        expect(
          updated_files.first.content
        ).to include "private-image-name-16.04\n"
        expect(updated_files.first.content).to include "tag: 20190825090000\n"
      end

      it "correctly updates the input files if we use the bootstrapme tags" do
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "20200308093045" }
          }]

        expected_previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "bootstrapme" }
          }]

        input_files = Dependabot::DependencyFile.new(
          name: "pix4d-special.yml",
          content: fixture("pipelines", "pix4d-special.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "private.repo.com/private-image-name-16.04",
          version: "20200308093045",
          previous_version: "bootstrapme",
          requirements: expected_requirements,
          previous_requirements: expected_previous_requirements,
          package_manager: "docker"
        )

        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("pix4d-special.yml")
        expect(
          updated_files.first.content
        ).to include "private-image-name-16.04\n"
        expect(updated_files.first.content).to include "tag: 20200308093045\n"
      end

      it "correctly updates the input files if we use double \
         quotes around tags" do
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "20200309103030" }
          }]

        expected_previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "20200220151020" }
          }]

        input_files = Dependabot::DependencyFile.new(
          name: "pix4d-special.yml",
          content: fixture("pipelines", "pix4d-special.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "private.repo.com/private-image-name-18.04",
          version: "20200309103030",
          previous_version: "20200220151020",
          requirements: expected_requirements,
          previous_requirements: expected_previous_requirements,
          package_manager: "docker"
        )
        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("pix4d-special.yml")
        expect(
          updated_files.first.content
        ).to include "private-image-name-18.04\n"
        expect(updated_files.first.content).to include "tag: 20200309103030\n"
      end

      it "correctly updates the input files if we use the bootstrapme \
         tags with double quotes" do
        expected_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "20200306093045" }
          }]

        expected_previous_requirements =
          [{
            requirement: nil,
            groups: [],
            file: "pix4d-special.yml",
            source: { tag: "bootstrapme" }
          }]

        input_files = Dependabot::DependencyFile.new(
          name: "pix4d-special.yml",
          content: fixture("pipelines", "pix4d-special.yml")
        )

        input_dependencies = Dependabot::Dependency.new(
          name: "private.repo.com/private-image-name",
          version: "20200306093045",
          previous_version: "bootstrapme",
          requirements: expected_requirements,
          previous_requirements: expected_previous_requirements,
          package_manager: "docker"
        )

        updater = described_class.new(
          dependencies: [input_dependencies],
          dependency_files: [input_files],
          credentials: nil
        )

        updated_files = updater.updated_dependency_files
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.first.name).to eq("pix4d-special.yml")
        expect(updated_files.first.content).to include "private-image-name\n"
        expect(updated_files.first.content).to include "tag: 20200306093045\n"
      end
    end
  end
end
