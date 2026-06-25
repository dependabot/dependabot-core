# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/maven/shared/shared_property_value_updater"

RSpec.describe Dependabot::Maven::Shared::SharedPropertyValueUpdater do
  # Concrete subclass with a stub PropertyValueFinder for testing
  let(:finder_class) do
    Class.new do
      def initialize(dependency_files:)
        @dependency_files = dependency_files
      end

      def property_details(property_name:, callsite_buildfile: nil) # rubocop:disable Lint/UnusedMethodArgument
        @dependency_files.each do |file|
          file.content&.scan(
            /(?:^|\s)(?:lazy\s+)?val\s+#{Regexp.quote(property_name)}(?:\s*:\s*String)?\s*=\s*"([^"]+)"/
          ) do
            declaration = Regexp.last_match.to_s.strip
            return {
              value: Regexp.last_match(1),
              declaration_string: declaration,
              file: file.name
            }
          end
        end
        nil
      end
    end
  end

  let(:updater_class) do
    fc = finder_class
    Class.new(described_class) do
      define_method(:property_value_finder) do
        @property_value_finder ||= fc.new(dependency_files: dependency_files)
      end
    end
  end

  let(:updater) { updater_class.new(dependency_files: dependency_files) }

  describe "#update_files_for_property_change" do
    subject(:updated_files) do
      updater.update_files_for_property_change(
        property_name: property_name,
        callsite_buildfile: callsite_buildfile,
        previous_value: previous_value,
        updated_value: updated_value
      )
    end

    context "when the property is in the callsite file" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: <<~SBT
            val catsVersion = "2.10.0"

            libraryDependencies += "org.typelevel" %% "cats-core" % catsVersion
          SBT
        )
      end
      let(:dependency_files) { [buildfile] }
      let(:callsite_buildfile) { buildfile }
      let(:property_name) { "catsVersion" }
      let(:previous_value) { "2.10.0" }
      let(:updated_value) { "2.11.0" }

      it "returns an array of DependencyFile objects" do
        expect(updated_files).to all(be_a(Dependabot::DependencyFile))
      end

      it "updates the val declaration" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to include('val catsVersion = "2.11.0"')
        expect(updated.content).not_to include('val catsVersion = "2.10.0"')
      end

      it "does not change the dependency reference line" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to include('"org.typelevel" %% "cats-core" % catsVersion')
      end

      it "preserves the total number of files" do
        expect(updated_files.length).to eq(dependency_files.length)
      end
    end

    context "when the property is in a different file" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: <<~SBT
            libraryDependencies += "org.typelevel" %% "cats-core" % catsVersion
          SBT
        )
      end
      let(:scala_file) do
        Dependabot::DependencyFile.new(
          name: "project/Dependencies.scala",
          content: <<~SCALA
            import sbt._

            object Dependencies {
              val catsVersion = "2.10.0"
              val akkaVersion = "2.8.5"
            }
          SCALA
        )
      end
      let(:dependency_files) { [buildfile, scala_file] }
      let(:callsite_buildfile) { buildfile }
      let(:property_name) { "catsVersion" }
      let(:previous_value) { "2.10.0" }
      let(:updated_value) { "2.11.0" }

      it "updates the val in the Scala file" do
        updated = updated_files.find { |f| f.name == "project/Dependencies.scala" }
        expect(updated.content).to include('val catsVersion = "2.11.0"')
        expect(updated.content).not_to include('val catsVersion = "2.10.0"')
      end

      it "does not modify the buildfile content" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to eq(buildfile.content)
      end

      it "leaves other properties unchanged" do
        updated = updated_files.find { |f| f.name == "project/Dependencies.scala" }
        expect(updated.content).to include('val akkaVersion = "2.8.5"')
      end
    end

    context "with a lazy val declaration" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: <<~SBT
            lazy val guavaVersion = "33.0.0-jre"

            libraryDependencies += "com.google.guava" % "guava" % guavaVersion
          SBT
        )
      end
      let(:dependency_files) { [buildfile] }
      let(:callsite_buildfile) { buildfile }
      let(:property_name) { "guavaVersion" }
      let(:previous_value) { "33.0.0-jre" }
      let(:updated_value) { "33.1.0-jre" }

      it "updates the lazy val declaration" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to include('lazy val guavaVersion = "33.1.0-jre"')
        expect(updated.content).not_to include('"33.0.0-jre"')
      end
    end

    context "with a typed val declaration" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: <<~SBT
            val guavaVersion: String = "33.0.0-jre"

            libraryDependencies += "com.google.guava" % "guava" % guavaVersion
          SBT
        )
      end
      let(:dependency_files) { [buildfile] }
      let(:callsite_buildfile) { buildfile }
      let(:property_name) { "guavaVersion" }
      let(:previous_value) { "33.0.0-jre" }
      let(:updated_value) { "33.1.0-jre" }

      it "updates the typed val declaration" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to include('val guavaVersion: String = "33.1.0-jre"')
        expect(updated.content).not_to include('"33.0.0-jre"')
      end
    end

    context "when the value appears in multiple places but only updates the declaration" do
      let(:buildfile) do
        Dependabot::DependencyFile.new(
          name: "build.sbt",
          content: <<~SBT
            val akkaVersion = "2.8.5"

            // akka is pinned to "2.8.5" for stability
            libraryDependencies += "com.typesafe.akka" %% "akka-actor" % akkaVersion
          SBT
        )
      end
      let(:dependency_files) { [buildfile] }
      let(:callsite_buildfile) { buildfile }
      let(:property_name) { "akkaVersion" }
      let(:previous_value) { "2.8.5" }
      let(:updated_value) { "2.9.0" }

      it "only updates the val declaration, not the comment" do
        updated = updated_files.find { |f| f.name == "build.sbt" }
        expect(updated.content).to include('val akkaVersion = "2.9.0"')
        # The comment still has the old version since sub only replaces the first match
        expect(updated.content).to include('// akka is pinned to "2.8.5" for stability')
      end
    end
  end
end
