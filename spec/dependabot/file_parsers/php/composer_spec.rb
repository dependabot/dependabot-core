# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/file_parsers/php/composer"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Php::Composer do
  it_behaves_like "a dependency file parser"

  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: composer_json_body
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: lockfile_body
    )
  end
  let(:composer_json_body) do
    fixture("php", "composer_files", composer_json_fixture_name)
  end
  let(:lockfile_body) { fixture("php", "lockfiles", lockfile_fixture_name) }
  let(:composer_json_fixture_name) { "minor_version" }
  let(:lockfile_fixture_name) { "minor_version" }
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

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        it { is_expected.to be_production }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) { is_expected.to eq("1.0.2") }
        its(:requirements) do
          is_expected.to eq(
            [{
              requirement: "1.0.*",
              file: "composer.json",
              groups: ["runtime"],
              source: {
                type: "git",
                url: "https://github.com/Seldaek/monolog.git"
              }
            }]
          )
        end
      end
    end

    context "for development dependencies" do
      let(:composer_json_fixture_name) { "development_dependencies" }
      let(:lockfile_fixture_name) { "development_dependencies" }

      it "includes development dependencies" do
        expect(dependencies.length).to eq(2)
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        it { is_expected.to_not be_production }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) { is_expected.to eq("1.0.1") }
        its(:requirements) do
          is_expected.to eq(
            [{
              requirement: "1.0.1",
              file: "composer.json",
              groups: ["development"],
              source: {
                type: "git",
                url: "https://github.com/Seldaek/monolog.git"
              }
            }]
          )
        end
      end
    end

    context "with the PHP version specified" do
      let(:composer_json_fixture_name) { "php_specified" }
      let(:lockfile_fixture_name) { "php_specified" }

      its(:length) { is_expected.to eq(5) }

      describe "top level dependencies" do
        subject { dependencies.select(&:top_level?) }
        its(:length) { is_expected.to eq(2) }
      end
    end

    context "with a version with a 'v' prefix" do
      let(:lockfile_fixture_name) { "v_prefix" }

      it "strips the prefix" do
        expect(dependencies.first.version).to eq("1.0.2")
      end
    end

    context "with a non-numeric version" do
      let(:lockfile_fixture_name) { "git_source" }

      it "skips the dependency" do
        expect(dependencies.length).to eq(1)
      end
    end

    context "with a gutted lockfile" do
      let(:lockfile_fixture_name) { "gutted" }

      it "skips the dependency" do
        expect(dependencies.length).to eq(0)
      end
    end

    context "with a path dependency" do
      let(:files) { [composer_json, lockfile, path_dep] }
      let(:composer_json_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source" }
      let(:path_dep) do
        Dependabot::DependencyFile.new(
          name: "components/path_dep/composer.json",
          content: fixture("php", "composer_files", "path_dep")
        )
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        it { is_expected.to be_production }
        its(:name) { is_expected.to eq("path_dep/path_dep") }
        its(:version) { is_expected.to eq("1.0.1") }
        its(:requirements) do
          is_expected.to eq(
            [{
              requirement: "1.0.*",
              file: "composer.json",
              groups: ["runtime"],
              source: { type: "path" }
            }]
          )
        end
      end
    end

    context "without a lockfile" do
      let(:files) { [composer_json] }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) { is_expected.to be_nil }
        its(:requirements) do
          is_expected.to eq(
            [{
              requirement: "1.0.*",
              file: "composer.json",
              groups: ["runtime"],
              source: nil
            }]
          )
        end
      end

      context "for development dependencies" do
        let(:composer_json_fixture_name) { "development_dependencies" }

        it "includes development dependencies" do
          expect(dependencies.length).to eq(2)
        end

        describe "the first dependency" do
          subject { dependencies.first }

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("monolog/monolog") }
          its(:version) { is_expected.to be_nil }
          its(:requirements) do
            is_expected.to eq(
              [{
                requirement: "1.0.1",
                file: "composer.json",
                groups: ["development"],
                source: nil
              }]
            )
          end
        end
      end

      context "with the PHP version specified" do
        let(:composer_json_fixture_name) { "php_specified" }
        its(:length) { is_expected.to eq(2) }
      end
    end

    context "with a bad lockfile" do
      let(:lockfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies.length }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("composer.lock")
          end
      end
    end

    context "with a bad composer.json" do
      let(:composer_json_body) { fixture("ruby", "gemfiles", "Gemfile") }

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies.length }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("composer.json")
          end
      end
    end
  end
end
