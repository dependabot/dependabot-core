# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/docker/docker"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Docker::Docker do
  it_behaves_like "a dependency file parser"

  let(:files) { [dockerfile] }
  let(:dockerfile) do
    Dependabot::DependencyFile.new(
      name: "Dockerfile",
      content: dockerfile_body
    )
  end
  let(:dockerfile_body) { fixture("docker", "dockerfiles", "tag") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(1) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("ubuntu")
        expect(dependency.version).to eq("17.04")
        expect(dependency.requirements).to eq([])
      end
    end

    context "with no tag or digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "bare") }
      its(:length) { is_expected.to eq(0) }
    end

    context "with a name" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "name") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq([])
        end
      end
    end

    context "with a namespace" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "namespace") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("library/ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq([])
        end
      end
    end

    context "with a FROM line written by a nutcase" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "case") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("17.04")
          expect(dependency.requirements).to eq([])
        end
      end
    end

    context "with a digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "digest") }

      # TODO: support digests
      its(:length) { is_expected.to eq(0) }
    end

    context "with a private registry and a tag" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "private_tag") }

      # TODO: support private registries
      its(:length) { is_expected.to eq(0) }
    end
  end
end
