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

  describe "inheritance" do
    require_common_spec "file_parsers/shared_examples_for_file_parsers"

    it_behaves_like "a dependency file parser"
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

      context "with an aliased dependency" do
        let(:files) { project_dependency_files("bun/aliased_dependency") }

        it "doesn't include the aliased dependency" do
          expect(top_level_dependencies.map(&:name)).to eq(["etag"])
          expect(dependencies.map(&:name)).not_to include("my-fetch-factory")
        end

        it "includes the real package from the lockfile" do
          expect(dependencies.map(&:name)).to include("fetch-factory")
        end
      end
    end
  end

  describe "alias detection" do
    let(:files) { project_dependency_files("bun/aliased_dependency") }

    it "detects the npm alias protocol in a requirement" do
      expect(parser.send(:alias_package?, "npm:fetch-factory@0.0.1")).to be(true)
      expect(parser.send(:alias_package?, "npm:@scope/pkg@^1.0.0")).to be(true)
      expect(parser.send(:alias_package?, "^0.0.1")).to be(false)
    end

    it "detects a yarn-style alias in a name" do
      expect(parser.send(:aliased_package_name?, "my-fetch-factory@npm:fetch-factory")).to be(true)
      expect(parser.send(:aliased_package_name?, "fetch-factory")).to be(false)
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
