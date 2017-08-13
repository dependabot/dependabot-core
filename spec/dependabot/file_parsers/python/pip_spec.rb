# frozen_string_literal: true
require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/python/pip"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Python::Pip do
  it_behaves_like "a dependency file parser"

  let(:files) { [requirements] }
  let(:requirements) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: requirements_body
    )
  end
  let(:requirements_body) do
    fixture("python", "requirements", "version_specified.txt")
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with comments" do
      let(:requirements_body) do
        fixture("python", "requirements", "comments.txt")
      end
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with extras" do
      let(:requirements_body) do
        fixture("python", "requirements", "extras.txt")
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with invalid lines" do
      let(:requirements_body) do
        fixture("python", "requirements", "invalid_lines.txt")
      end

      it "raises a Dependabot::DependencyFileNotEvaluatable error" do
        expect { parser.parse }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "with no version specified" do
      let(:requirements_body) do
        fixture("python", "requirements", "version_not_specified.txt")
      end

      # If no version is specified, Python will always use the latest, and we
      # don't need to attempt to bump the dependency.
      its(:length) { is_expected.to eq(1) }
    end

    context "with a version specified as between two constraints" do
      let(:requirements_body) do
        fixture("python", "requirements", "version_between_bounds.txt")
      end

      # TODO: For now we ignore dependencies with multiple requirements, because
      # they would cause trouble at the dependency update step.
      its(:length) { is_expected.to eq(1) }
    end

    context "with reference to its setup.py" do
      let(:files) { [requirements, setup_file] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("python", "requirements", "with_setup_path.txt")
        )
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("python", "setup_files", "setup.py")
        )
      end

      # Path based dependencies get ignored
      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("requests") }
        its(:version) { is_expected.to eq(Gem::Version.new("2.1.4")) }
      end
    end

    context "with child requirement files" do
      let(:files) { [requirements, child_requirements] }
      let(:requirements) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("python", "requirements", "cascading.txt")
        )
      end
      let(:child_requirements) do
        Dependabot::DependencyFile.new(
          name: "more_requirements.txt",
          content: fixture("python", "requirements", "version_specified.txt")
        )
      end

      its(:length) { is_expected.to eq(3) }
    end
  end
end
