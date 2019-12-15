# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/sbt/file_parser/scala_versions_finder"

RSpec.describe Dependabot::Sbt::FileParser::ScalaVersionsFinder do
  let(:files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.sbt",
      content: fixture("buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "cross_scala_version_build.sbt" }
  let(:scala_versions_finder) { described_class.new(dependency_files: files) }

  describe "scala versions finder" do
    subject(:versions) { scala_versions_finder.cross_build_versions }

    it "retrieves the scalaVersion string" do
      expect(versions.length).to eq(1)
      expect(versions[0]).to eq("2.11")
    end
  end

  context "when scalaVersion not specified" do
    let(:buildfile_fixture_name) { "no_scala_version_specified_build.sbt" }

    describe "find" do
      subject(:versions) { scala_versions_finder.cross_build_versions }

      it "retrieves no scala versions" do
        expect(versions).to be_empty
      end
    end
  end
end
