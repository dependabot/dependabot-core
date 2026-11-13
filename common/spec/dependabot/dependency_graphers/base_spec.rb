# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency_graphers/base"
require "dependabot/file_parsers/base"
require "dependabot/source"

RSpec.describe Dependabot::DependencyGraphers::Base do
  subject(:grapher) { grapher_class.new(file_parser: parser) }

  let(:parser_class) do
    Class.new(Dependabot::FileParsers::Base) do
      def parse
        []
      end

      private

      def check_required_files; end
    end
  end

  let(:grapher_class) do
    Class.new(described_class) do
      def relevant_dependency_file
        dependency_files.first
      end

      private

      def fetch_subdependencies(_dependency)
        []
      end

      def purl_pkg_for(_dependency)
        "generic"
      end
    end
  end

  let(:parser) do
    parser_class.new(
      dependency_files: dependency_files,
      source: Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/")
    )
  end

  let(:manifest) { file("app.manifest") }
  let(:lockfile) { file("app.lock") }
  let(:dependency_files) { [manifest, lockfile] }

  def file(name)
    Dependabot::DependencyFile.new(name: name, content: "", directory: "/")
  end

  describe "#manifest_set_input_files" do
    it "returns every file of a single group" do
      expect(grapher.manifest_set_input_files.map(&:path)).to eq(["/app.manifest", "/app.lock"])
    end

    context "when the directory resolves as several manifest groups" do
      let(:tests_manifest) { file("tests.manifest") }
      let(:tests_lockfile) { file("tests.lock") }
      let(:unrelated) { file("README.md") }
      let(:dependency_files) { [manifest, lockfile, tests_manifest, tests_lockfile, unrelated] }

      let(:grapher_class) do
        groups = [
          Dependabot::DependencyGraphers::ManifestGroup.new(primary: lockfile, files: [manifest, lockfile]),
          Dependabot::DependencyGraphers::ManifestGroup.new(
            primary: tests_lockfile, files: [tests_manifest, tests_lockfile, lockfile]
          )
        ]
        Class.new(super()) { define_method(:manifest_groups) { groups } }
      end

      it "returns the union of every group's files, once each, and nothing outside the groups" do
        expect(grapher.manifest_set_input_files.map(&:path))
          .to eq(["/app.manifest", "/app.lock", "/tests.manifest", "/tests.lock"])
      end

      it "resolves each group so the snapshots match the groups" do
        grapher.manifest_set_input_files

        expect(grapher.manifest_group_snapshots.map { |s| s.manifest_file.name })
          .to eq(["app.lock", "tests.lock"])
      end
    end

    context "when preparation generates a file that was not fetched from the repository" do
      let(:grapher_class) do
        Class.new(super()) do
          def prepare!
            dependency_files << Dependabot::DependencyFile.new(name: "generated.lock", content: "", directory: "/")
            super
          end
        end
      end

      it "excludes the generated file" do
        expect(grapher.manifest_set_input_files.map(&:name)).to eq(["app.manifest", "app.lock"])
      end
    end

    context "when the ecosystem excludes files that do not affect resolution" do
      let(:grapher_class) do
        Class.new(super()) do
          private

          def manifest_set_input_file?(file)
            file.name != "app.lock"
          end
        end
      end

      it "applies the ecosystem's filter" do
        expect(grapher.manifest_set_input_files.map(&:name)).to eq(["app.manifest"])
      end
    end
  end
end
