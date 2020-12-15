# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/composer/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Composer::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "minor_version" }
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

    context "with a version specified (composer v1)" do
      let(:project_name) { "v1/minor_version" }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
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

    context "with doctored entries" do
      let(:project_name) { "doctored" }
      its(:length) { is_expected.to eq(2) }
    end

    context "with an integer version" do
      let(:project_name) { "integer_version" }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) do
          is_expected.to eq("wpackagist-plugin/ga-google-analytics")
        end
        its(:version) { is_expected.to eq("20180828") }
      end
    end

    context "for development dependencies" do
      let(:project_name) { "development_dependencies" }

      it "includes development dependencies" do
        expect(dependencies.length).to eq(2)
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
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
      let(:project_name) { "php_specified" }

      its(:length) { is_expected.to eq(5) }

      describe "top level dependencies" do
        subject { dependencies.select(&:top_level?) }
        its(:length) { is_expected.to eq(2) }
      end
    end

    context "with subdependencies" do
      let(:project_name) { "development_subdependencies" }

      its(:length) { is_expected.to eq(16) }

      describe "top level dependencies" do
        subject { dependencies.select(&:top_level?) }
        its(:length) { is_expected.to eq(2) }
      end

      describe "a production subdependency" do
        subject(:subdep) do
          dependencies.find { |d| d.name == "symfony/polyfill-ctype" }
        end

        it "parses the details correctly" do
          expect(subdep.version).to eq("1.11.0")
          expect(subdep.subdependency_metadata).to eq([{ production: true }])
        end
      end

      describe "a development subdependency" do
        subject(:subdep) do
          dependencies.find { |d| d.name == "phpunit/php-token-stream" }
        end

        it "parses the details correctly" do
          expect(subdep.version).to eq("3.1.0")
          expect(subdep.subdependency_metadata).to eq([{ production: false }])
        end
      end
    end

    context "with a version with a 'v' prefix" do
      let(:project_name) { "v_prefix" }

      it "strips the prefix" do
        expect(dependencies.first.version).to eq("1.0.2")
      end
    end

    context "with a git dependency" do
      let(:project_name) { "git_source" }

      it "includes the dependency" do
        expect(dependencies.length).to eq(2)
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("monolog/monolog") }
        its(:version) do
          is_expected.to eq("5267b03b1e4861c4657ede17a88f13ef479db482")
        end
        its(:requirements) do
          is_expected.to eq(
            [{
              requirement: "dev-example",
              file: "composer.json",
              groups: ["runtime"],
              source: {
                type: "git",
                url: "https://github.com/dependabot/monolog.git",
                branch: "example",
                ref: nil
              }
            }]
          )
        end

        context "specified as an alias" do
          let(:project_name) { "git_source_alias" }

          its(:requirements) do
            is_expected.to eq(
              [{
                requirement: "dev-example as 1.0.2",
                file: "composer.json",
                groups: ["runtime"],
                source: {
                  type: "git",
                  url: "https://github.com/dependabot/monolog.git",
                  branch: "example",
                  ref: nil
                }
              }]
            )
          end
        end

        context "due to a stability flag" do
          subject { dependencies.last }

          let(:project_name) { "git_source_transitive" }

          its(:requirements) do
            is_expected.to eq(
              [{
                requirement: "1.*@dev",
                file: "composer.json",
                groups: ["runtime"],
                source: {
                  type: "git",
                  url: "https://github.com/php-fig/log.git",
                  branch: "master",
                  ref: nil
                }
              }]
            )
          end
        end
      end
    end

    context "with a gutted lockfile" do
      let(:project_name) { "gutted" }

      it "skips the dependency" do
        expect(dependencies.length).to eq(0)
      end
    end

    context "with a path dependency" do
      let(:project_name) { "path_source" }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
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
      let(:project_name) { "minor_version_without_lockfile" }

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
        let(:project_name) { "development_dependencies_without_lockfile" }

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
        let(:project_name) { "php_specified_without_lockfile" }
        its(:length) { is_expected.to eq(2) }
      end

      context "with a git dependency" do
        let(:project_name) { "git_source_without_lockfile" }

        it "includes the dependency" do
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
                requirement: "dev-example",
                file: "composer.json",
                groups: ["runtime"],
                source: nil
              }]
            )
          end
        end
      end
    end

    context "with a bad lockfile" do
      let(:project_name) { "unparseable_lockfile" }

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies.length }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("composer.lock")
          end
      end
    end

    context "with a bad composer.json" do
      let(:project_name) { "unparseable_composer_json" }

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies.length }.
          to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("composer.json")
          end
      end
    end
  end
end
