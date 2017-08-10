# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/python/pip"
require "dependabot/shared_helpers"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Python::Pip do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [requirements],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:requirements) do
    Dependabot::DependencyFile.new(
      content: requirements_body,
      name: "requirements.txt"
    )
  end
  let(:requirements_body) do
    fixture("python", "requirements", "version_specified.txt")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "psycopg2",
      version: "2.8.1",
      package_manager: "pip"
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated requirements_file" do
      subject(:updated_requirements_file) do
        updated_files.find { |f| f.name == "requirements.txt" }
      end

      its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
      its(:content) { is_expected.to include "luigi==2.2.0\n" }

      context "when only the minor version is specified" do
        let(:requirements_body) do
          fixture("python", "requirements", "minor_version_specified.txt")
        end

        its(:content) { is_expected.to include "psycopg2==2.8\n" }
      end

      context "when there is a comment" do
        let(:requirements_body) do
          fixture("python", "requirements", "comments.txt")
        end
        its(:content) { is_expected.to include "psycopg2==2.8.1  # Comment!\n" }
      end

      context "when there are unused lines" do
        let(:requirements_body) do
          fixture("python", "requirements", "invalid_lines.txt")
        end
        its(:content) { is_expected.to include "psycopg2==2.8.1\n" }
        its(:content) { is_expected.to include "# This is just a comment" }
      end

      context "when the dependency is in a child requirement file" do
        subject(:updated_requirements_file) do
          updated_files.find { |f| f.name == "more_requirements.txt" }
        end

        let(:updater) do
          described_class.new(
            dependency_files: [requirements, more_requirements],
            dependency: dependency,
            github_access_token: "token"
          )
        end

        let(:requirements_body) do
          fixture("python", "requirements", "cascading.txt")
        end

        let(:more_requirements) do
          Dependabot::DependencyFile.new(
            content: fixture("python", "requirements", "version_specified.txt"),
            name: "more_requirements.txt"
          )
        end

        it "updates and returns the right file" do
          expect(updated_files.count).to eq(1)
          expect(updated_files.first.content).to include("psycopg2==2.8.1\n")
        end
      end
    end
  end

  describe Dependabot::FileUpdaters::Python::Pip::LineParser do
    describe ".parse" do
      subject { described_class.parse(line) }

      context "with a blank line" do
        let(:line) { "" }
        it { is_expected.to be_nil }
      end

      context "with just a line break" do
        let(:line) { "\n" }
        it { is_expected.to be_nil }
      end

      context "with a non-requirement line" do
        let(:line) { "# This is just a comment" }
        it { is_expected.to be_nil }
      end

      context "with no specification" do
        let(:line) { "luigi" }
        its([:name]) { is_expected.to eq "luigi" }
        its([:requirements]) { is_expected.to eq [] }

        context "with a comment" do
          let(:line) { "luigi # some comment" }
          its([:name]) { is_expected.to eq "luigi" }
          its([:requirements]) { is_expected.to eq [] }
        end
      end

      context "with a simple specification" do
        let(:line) { "luigi == 0.1.0" }
        its([:requirements]) do
          is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
        end

        context "without spaces" do
          let(:line) { "luigi==0.1.0" }
          its([:name]) { is_expected.to eq "luigi" }
          its([:requirements]) do
            is_expected.to eq [{ comparison: "==", version: "0.1.0" }]
          end
        end
      end

      context "with multiple specifications" do
        let(:line) { "luigi == 0.1.0, <= 1" }
        its([:requirements]) do
          is_expected.to eq([
                              { comparison: "==", version: "0.1.0" },
                              { comparison: "<=", version: "1" }
                            ])
        end

        context "with a comment" do
          let(:line) { "luigi == 0.1.0, <= 1 # some comment" }
          its([:requirements]) do
            is_expected.to eq([
                                { comparison: "==", version: "0.1.0" },
                                { comparison: "<=", version: "1" }
                              ])
          end
        end
      end
    end
  end
end
