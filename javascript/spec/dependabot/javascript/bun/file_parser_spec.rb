# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Javascript::Bun::FileParser do
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
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
    end
  end

  describe "missing package.json manifest file" do
    let(:child_class) do
      Class.new(described_class) do
        def check_required_files
          %w(manifest).each do |filename|
            unless get_original_file(filename)
              raise Dependabot::DependencyFileNotFound.new(nil,
                                                           "package.json not found.")
            end
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
