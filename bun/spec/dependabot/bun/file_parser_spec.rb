# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::FileParser do
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source,
      credentials: credentials
    )
  end

  describe ".each_dependency compatibility" do
    it "keeps raw values and section order for updater callers" do
      json = {
        "dependencies" => { "first" => "1.0.0", "raw" => { "version" => "2.0.0" }, "missing" => nil },
        "devDependencies" => { "first" => "3.0.0" }
      }
      yielded = []

      described_class.each_dependency(json) { |name, requirement, type| yielded << [name, requirement, type] }

      expect(yielded).to eq(
        [
          ["first", "1.0.0", "dependencies"],
          ["raw", { "version" => "2.0.0" }, "dependencies"],
          ["missing", nil, "dependencies"],
          ["first", "3.0.0", "devDependencies"]
        ]
      )
    end

    it "allows callbacks to change the original dependency map" do
      json = { "dependencies" => { "first" => "1.0.0", "second" => "2.0.0" } }
      yielded = []

      described_class.each_dependency(json) do |name, requirement, type|
        yielded << requirement
        json[type]["second"] = "3.0.0" if name == "first"
      end

      expect(yielded).to eq(["1.0.0", "3.0.0"])
      expect(json["dependencies"]["second"]).to eq("3.0.0")
    end
  end

  describe "package.json read boundaries" do
    let(:manifest) { { "name" => "root", "dependencies" => { "chalk" => "0.3.0" } } }
    let(:manifest_content) { JSON.dump(manifest) }
    let(:package_file) { Dependabot::DependencyFile.new(name: "package.json", content: manifest_content) }
    let(:files) { [package_file] }

    it "parses an exact dependency without a lockfile" do
      expect(parser.parse.map(&:name)).to eq(["chalk"])
    end

    context "with non-string and workspace/catalog requirements" do
      let(:manifest) do
        {
          "dependencies" => {
            "chalk" => "0.3.0",
            "raw" => { "version" => "1.0.0" },
            "missing" => nil,
            "workspace" => "workspace:*",
            "catalog" => "catalog:testing"
          }
        }
      end

      it "keeps only the registry dependency" do
        expect(parser.parse.map(&:name)).to eq(["chalk"])
      end
    end

    context "with an empty requirement" do
      let(:manifest) { { "dependencies" => { "chalk" => "" } } }

      it "retains wildcard normalization" do
        dependency = parser.parse.find { |dep| dep.name == "chalk" }

        expect(dependency.requirements.first.requirement_string).to eq("*")
      end
    end

    context "with malformed dependency containers" do
      let(:manifest) { { "dependencies" => [["chalk", "0.3.0"]] } }

      it "rejects the container with file and field context" do
        expect { parser.parse }
          .to raise_error(TypeError, "#{package_file.path}: dependencies must be an object")
      end
    end

    context "with a flat manifest and malformed dependencies" do
      let(:manifest) { { "flat" => true, "dependencies" => [] } }

      it "skips the manifest before inspecting dependencies" do
        expect(parser.parse).to be_empty
      end
    end

    context "with missing, null, and false dependency sections" do
      let(:manifest) { { "dependencies" => nil, "devDependencies" => false } }

      it "finds no dependencies" do
        expect(parser.parse).to be_empty
      end
    end

    context "with a workspace package" do
      let(:manifest) { { "dependencies" => { "chalk" => "0.3.0", "member" => "1.0.0" } } }
      let(:member_name) { "member" }
      let(:files) do
        [
          package_file,
          Dependabot::DependencyFile.new(
            name: "packages/member/package.json",
            content: JSON.dump("name" => member_name)
          )
        ]
      end

      it "excludes the workspace package from registry updates" do
        expect(parser.parse.map(&:name)).to eq(["chalk"])
      end

      context "with a non-string workspace name" do
        let(:member_name) { 123 }

        it "does not match the dependency name" do
          expect(parser.parse.map(&:name)).to contain_exactly("chalk", "member")
        end
      end
    end

    context "with invalid JSON" do
      let(:manifest_content) { "{" }

      it "preserves the parsing error for dependency extraction" do
        expect { parser.parse }.to raise_error(JSON::ParserError)
      end

      it "preserves the file error for package-manager detection" do
        expect { parser.ecosystem }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end

  describe "inheritance" do
    require_common_spec "file_parsers/shared_examples_for_file_parsers"

    it_behaves_like "a dependency file parser"
  end

  describe "#ecosystem" do
    let(:files) { project_dependency_files("javascript/exact_version_requirements_no_lockfile") }

    before do
      allow(Dependabot::Bun::Helpers).to receive_messages(
        bun_version: "1.1.39",
        node_version: "20.0.0"
      )
    end

    it "builds package-manager metadata from the typed manifest config" do
      expect(parser.ecosystem.package_manager.name).to eq("bun")
    end
  end

  describe "parse" do
    subject(:dependencies) { parser.parse }

    describe "top level dependencies" do
      subject(:top_level_dependencies) { dependencies.select(&:top_level?) }

      context "with no lockfile" do
        let(:files) { project_dependency_files("javascript/exact_version_requirements_no_lockfile") }

        its(:length) { is_expected.to eq(3) }

        describe "the first dependency" do
          subject { top_level_dependencies.first }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("chalk") }
          its(:version) { is_expected.to eq("0.3.0") }
        end
      end

      context "with no lockfile, and non exact requirements" do
        let(:files) { project_dependency_files("javascript/file_version_requirements_no_lockfile") }

        its(:length) { is_expected.to eq(0) }
      end
    end
  end

  describe "missing package.json manifest file" do
    let(:child_class) do
      Class.new(described_class) do
        def check_required_files
          %w(manifest).each do |filename|
            next if get_original_file(filename)

            raise Dependabot::DependencyFileNotFound.new(
              nil,
              "package.json not found."
            )
          end
        end
      end
    end
    let(:parser_instance) do
      child_class.new(dependency_files: files, source: source)
    end
    let(:source) do
      Dependabot::Source.new(
        provider: "github",
        repo: "gocardless/bump",
        directory: "/"
      )
    end

    let(:gemfile) do
      Dependabot::DependencyFile.new(
        content: "a",
        name: "manifest",
        directory: "/path/to"
      )
    end
    let(:files) { [gemfile] }

    describe ".new" do
      context "when the required file is present" do
        let(:files) { [gemfile] }

        it "doesn't raise" do
          expect { parser_instance }.not_to raise_error
        end
      end

      context "when the required file is missing" do
        let(:files) { [] }

        it "raises" do
          expect { parser_instance }.to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    describe "#get_original_file" do
      subject { parser_instance.send(:get_original_file, filename) }

      context "when the requested file is present" do
        let(:filename) { "manifest" }

        it { is_expected.to eq(gemfile) }
      end

      context "when the requested file is not present" do
        let(:filename) { "package.json" }

        it { is_expected.to be_nil }
      end
    end
  end
end
