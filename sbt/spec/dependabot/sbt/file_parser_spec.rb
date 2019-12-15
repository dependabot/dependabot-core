# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/sbt/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Sbt::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.sbt" }
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("junit:junit-dep")
        expect(dependency.version).to eq("4.11")
        expect(dependency.requirements).to eq(
          [{
            requirement: "4.11",
            file: "build.sbt",
            groups: [],
            source: nil,
            metadata: {
              cross_scala_versions: []
            }
          }]
        )
      end
    end
  end

  context "including cross scala version dependencies" do
    let(:buildfile_fixture_name) { "cross_scala_version_build.sbt" }

    describe "parse" do
      subject(:dependencies) { parser.parse }

      its(:length) { is_expected.to eq(3) }

      describe "the library declared with %%" do
        subject(:dependency) do
          dependencies.find { |dep| dep.name.include? "org.scalatest" }
        end

        it "embeds scala version in artifact ID" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("org.scalatest:scalatest_2.11")
          expect(dependency.version).to eq("2.2.5")
          expect(dependency.requirements[0].fetch(:metadata).
                   fetch(:cross_scala_versions)).to eq(["2.11"])
        end
      end
    end
  end

  context "where dependencies are commented out" do
    let(:buildfile_fixture_name) { "commented_dependencies_build.sbt" }

    describe "parse" do
      subject(:dependencies) { parser.parse }

      its(:length) { is_expected.to eq(1) }

      it "embeds scala version in artifact ID" do
        dep = dependencies.first
        expect(dep).to be_a(Dependabot::Dependency)
        expect(dep.name).to eq("org.mutabilitydetector:MutabilityDetector")
        expect(dep.version).to eq("0.9.4-SNAPSHOT")
      end
    end
  end

  context "where dependencies use %%% syntax" do
    let(:buildfile_fixture_name) { "scalaz_build.sbt" }

    describe "parse" do
      subject(:dependencies) { parser.parse }

      it "retrieves none of them" do
        expect(dependencies).to be_empty
      end
    end
  end
end
