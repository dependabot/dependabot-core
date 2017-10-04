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

    context "with a digest" do
      let(:dockerfile_body) { fixture("docker", "dockerfiles", "digest") }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("ubuntu")
          expect(dependency.version).to eq("6ab3eaa4b3df")
          expect(dependency.requirements).to eq([])
        end
      end
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
  end
end
