# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/pipfile_files_parser"

RSpec.describe Dependabot::Python::FileParser::PipfileFilesParser do
  let(:parser) { described_class.new(dependency_files: files) }
  let(:files) { [pipfile, lockfile] }

  let(:pipfile) do
    Dependabot::DependencyFile.new(name: "Pipfile", content: pipfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Pipfile.lock", content: lockfile_body)
  end
  let(:pipfile_body) { fixture("pipfile_files", pipfile_fixture_name) }
  let(:lockfile_body) { fixture("pipfile_files", lockfile_fixture_name) }
  let(:pipfile_fixture_name) { "version_not_specified" }
  let(:lockfile_fixture_name) { "version_not_specified.lock" }

  describe "dependency_set" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    its(:length) { is_expected.to eq(7) }

    describe "top level dependencies" do
      subject(:dependencies) do
        parser.dependency_set.dependencies.select(&:top_level?)
      end

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.0") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    describe "sub-dependencies" do
      subject(:dependencies) do
        parser.dependency_set.dependencies.reject(&:top_level?)
      end

      its(:length) { is_expected.to eq(5) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("certifi") }
        its(:version) { is_expected.to eq("2017.11.5") }
        its(:requirements) { is_expected.to eq([]) }

        its(:subdependency_metadata) do
          is_expected.to eq([{ production: true }])
        end
      end

      describe "a development only dependency" do
        subject { dependencies.find { |d| d.name == "py" } }

        its(:subdependency_metadata) do
          is_expected.to eq([{ production: false }])
        end
      end

      describe "a development and production dependency" do
        subject { dependencies.find { |d| d.name == "py" } }

        let(:pipfile_fixture_name) { "prod_and_dev" }
        let(:lockfile_fixture_name) { "prod_and_dev.lock" }

        its(:subdependency_metadata) do
          is_expected.to eq([{ production: true }, { production: false }])
        end
      end
    end

    context "with a version specified" do
      let(:pipfile_fixture_name) { "exact_version" }
      let(:lockfile_fixture_name) { "exact_version.lock" }

      its(:length) { is_expected.to eq(11) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the last dependency" do
          subject { dependencies.last }

          let(:expected_requirements) do
            [{
              requirement: "==3.4.0",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("pytest") }
          its(:version) { is_expected.to eq("3.4.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end

      context "without a source" do
        let(:pipfile_fixture_name) { "no_source" }

        its(:length) { is_expected.to eq(11) }
      end

      context "when using arbitrary equality" do
        let(:pipfile_fixture_name) { "arbitrary_equality" }
        let(:lockfile_fixture_name) { "arbitrary_equality.lock" }

        describe "top level dependencies" do
          subject(:dependencies) do
            parser.dependency_set.dependencies.select(&:top_level?)
          end

          describe "the last dependency" do
            subject { dependencies.last }

            let(:expected_requirements) do
              [{
                requirement: "===3.4.0",
                file: "Pipfile",
                source: nil,
                groups: ["develop"]
              }]
            end

            it { is_expected.to be_a(Dependabot::Dependency) }
            its(:name) { is_expected.to eq("pytest") }
            its(:version) { is_expected.to eq("3.4.0") }
            its(:requirements) { is_expected.to eq(expected_requirements) }
          end
        end
      end
    end

    context "with only dev dependencies" do
      let(:pipfile_fixture_name) { "only_dev" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      its(:length) { is_expected.to eq(2) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the last dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["develop"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("pytest") }
          its(:version) { is_expected.to eq("3.2.3") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with dependency names that need normalising" do
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        # NOTE: This is a bug in Pipenv! The name `discord.py` is not being
        # properly normalised in the `Pipfile.lock`. Should be 4 once fixed.
        its(:length) { is_expected.to eq(3) }

        describe "the first dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with the version specified in a hash" do
      let(:pipfile_fixture_name) { "version_hash" }
      let(:lockfile_fixture_name) { "version_hash.lock" }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with the version specified in a declaration table" do
      let(:pipfile_fixture_name) { "version_table" }
      let(:lockfile_fixture_name) { "version_hash.lock" }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "==2.18.0",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "with a Pipfile that isn't parseable" do
      let(:pipfile_fixture_name) { "unparseable" }

      it "raises a Dependabot::DependencyFileNotParseable error" do
        expect { parser.dependency_set }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("Pipfile")
          end
      end
    end

    context "with a Pipfile.lock that isn't parseable" do
      let(:lockfile_fixture_name) { "unparseable.lock" }

      it "raises a Dependabot::DependencyFileNotParseable error" do
        expect { parser.dependency_set }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("Pipfile.lock")
          end
      end
    end

    context "with no entry in the Pipfile.lock" do
      let(:pipfile_fixture_name) { "not_in_lockfile" }
      let(:lockfile_fixture_name) { "only_dev.lock" }

      it "excludes the missing dependency" do
        expect(dependencies.map(&:name)).not_to include("missing")
      end

      describe "the dependency" do
        subject { dependencies.find { |d| d.name == "pytest" } }

        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["develop"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("pytest") }
        its(:version) { is_expected.to eq("3.2.3") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a git source" do
      let(:pipfile_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source.lock" }

      it "excludes the git dependency" do
        expect(dependencies.map(&:name)).not_to include("pythonfinder")
      end

      describe "the (non-git) dependency" do
        subject { dependencies.find { |d| d.name == "requests" } }

        let(:expected_requirements) do
          [{
            requirement: "*",
            file: "Pipfile",
            source: nil,
            groups: ["default"]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq("2.18.4") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
      end
    end

    context "with a lockfile that has been edited" do
      # This lockfile has been edited to have a string version for requests
      # (rather than a hash) and an array of garbage as the version for one
      # of the subdependencies. The formed is allowed through, the later is
      # excluded.
      let(:lockfile_fixture_name) { "edited.lock" }

      its(:length) { is_expected.to eq(6) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(1) }

        describe "the first dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to eq("2.18.0") }
          its(:requirements) { is_expected.to eq(expected_requirements) }
        end
      end
    end

    context "without a lockfile" do
      let(:files) { [pipfile] }

      its(:length) { is_expected.to eq(2) }

      describe "top level dependencies" do
        subject(:dependencies) do
          parser.dependency_set.dependencies.select(&:top_level?)
        end

        its(:length) { is_expected.to eq(2) }

        describe "the first dependency" do
          subject { dependencies.first }

          let(:expected_requirements) do
            [{
              requirement: "*",
              file: "Pipfile",
              source: nil,
              groups: ["default"]
            }]
          end

          it { is_expected.to be_a(Dependabot::Dependency) }
          its(:name) { is_expected.to eq("requests") }
          its(:version) { is_expected.to be_nil }
          its(:requirements) { is_expected.to eq(expected_requirements) }

          context "with exact versions specified in the Pipfile" do
            let(:pipfile_fixture_name) { "exact_version" }

            its(:version) { is_expected.to eq("2.18.0") }
          end

          context "with wildcard versions specified in the Pipfile" do
            let(:pipfile_fixture_name) { "wildcard" }

            its(:version) { is_expected.to be_nil }
          end
        end
      end
    end

    context "with an empty requirement string" do
      subject { dependencies.find { |d| d.name == "tensorflow-gpu" } }

      let(:pipfile_fixture_name) { "empty_requirement" }
      let(:files) { [pipfile] }
      let(:dependencies) do
        parser.dependency_set.dependencies.select(&:top_level?)
      end

      let(:expected_requirements) do
        [{
          requirement: "*",
          file: "Pipfile",
          source: nil,
          groups: ["develop"]
        }]
      end

      it { is_expected.to be_a(Dependabot::Dependency) }
      its(:name) { is_expected.to eq("tensorflow-gpu") }
      its(:requirements) { is_expected.to eq(expected_requirements) }
    end
  end
end
