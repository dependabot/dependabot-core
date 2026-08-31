# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/codeql/file_parser"

RSpec.describe Dependabot::Codeql::FileParser do
  subject(:parser) do
    described_class.new(dependency_files: files, source: source)
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "example/repo", directory: "/")
  end

  let(:qlpack_content) do
    <<~YAML
      name: example/queries
      version: 1.2.3
      dependencies:
        codeql/java-all: ^0.9.1
        codeql/javascript-all: "*"
        internal/shared: ${workspace}
    YAML
  end

  let(:lockfile_content) do
    <<~YAML
      dependencies:
        codeql/java-all:
          version: 0.9.2
        codeql/javascript-all:
          version: 0.9.8
        transitive/dep:
          version: 1.0.0
    YAML
  end

  let(:files) do
    [
      Dependabot::DependencyFile.new(name: "qlpack.yml", content: qlpack_content, directory: "/"),
      Dependabot::DependencyFile.new(name: "codeql-pack.lock.yml", content: lockfile_content, directory: "/")
    ]
  end

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "resolves direct dependencies from the lockfile" do
      expect(dependencies.map(&:name)).to eq(["codeql/java-all", "codeql/javascript-all"])
      expect(dependencies.map(&:version)).to eq(["0.9.2", "0.9.8"])
    end

    it "keeps the declared requirement ranges from the manifest" do
      expect(dependencies.map { |dep| dep.requirements.first[:requirement] }).to eq(["^0.9.1", "*"])
    end

    it "tags every dependency with the codeql package manager and registry source" do
      dependencies.each do |dep|
        expect(dep.package_manager).to eq("codeql")
        expect(dep.requirements.first[:source]).to eq(type: "codeql_pack_registry")
        expect(dep.requirements.first[:file]).to eq("qlpack.yml")
      end
    end

    it "returns dependencies sorted by name" do
      expect(dependencies.map(&:name)).to eq(dependencies.map(&:name).sort)
    end

    it "ignores ${workspace} source dependencies" do
      expect(dependencies.map(&:name)).not_to include("internal/shared")
    end

    context "with an unlocked wildcard dependency" do
      let(:qlpack_content) do
        <<~YAML
          name: example/queries
          dependencies:
            other/from-source: "*"
        YAML
      end
      let(:lockfile_content) { "dependencies: {}\n" }

      it "skips the from-source wildcard dependency" do
        expect(dependencies).to be_empty
      end
    end

    context "with a locked wildcard dependency" do
      let(:qlpack_content) do
        <<~YAML
          name: example/queries
          dependencies:
            other/pinned: "*"
        YAML
      end
      let(:lockfile_content) do
        <<~YAML
          dependencies:
            other/pinned:
              version: 2.3.4
        YAML
      end

      it "keeps the wildcard dependency with its locked version" do
        expect(dependencies.map(&:name)).to eq(["other/pinned"])
        expect(dependencies.first.version).to eq("2.3.4")
      end
    end

    context "without a lockfile" do
      let(:files) do
        [Dependabot::DependencyFile.new(name: "qlpack.yml", content: qlpack_content, directory: "/")]
      end
      let(:qlpack_content) do
        <<~YAML
          name: example/queries
          dependencies:
            codeql/java-all: ^0.9.1
        YAML
      end

      it "returns the dependency with a nil version" do
        expect(dependencies.map(&:name)).to eq(["codeql/java-all"])
        expect(dependencies.first.version).to be_nil
      end
    end

    context "with no dependencies section" do
      let(:qlpack_content) { "name: example/queries\nversion: 1.0.0\n" }
      let(:lockfile_content) { "dependencies: {}\n" }

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end
  end

  describe "#check_required_files" do
    context "without a qlpack.yml" do
      let(:files) do
        [Dependabot::DependencyFile.new(name: "codeql-pack.lock.yml", content: lockfile_content, directory: "/")]
      end

      it "raises an error" do
        expect { parser }.to raise_error("No qlpack.yml file!")
      end
    end
  end
end
