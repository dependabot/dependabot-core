# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/dependency_file_parsers/python"

RSpec.describe Bump::DependencyFileParsers::Python do
  let(:files) { [requirements] }
  let(:requirements) do
    Bump::DependencyFile.new(
      name: "requirements.txt",
      content: requirements_body
    )
  end
  let(:requirements_body) { fixture("requirements", "version_specified.txt") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with comments" do
      let(:requirements_body) { fixture("requirements", "comments.txt") }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with extras" do
      let(:requirements_body) { fixture("requirements", "extras.txt") }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with no version specified" do
      let(:requirements_body) do
        fixture("requirements", "version_not_specified.txt")
      end

      # If no version is specified, Python will always use the latest, and we
      # don't need to attempt to bump the dependency.
      its(:length) { is_expected.to eq(1) }
    end

    context "with a version specified as between two constraints" do
      let(:requirements_body) do
        fixture("requirements", "version_between_bounds.txt")
      end

      # TODO: For now we ignore dependencies with multiple requirements, because
      # they'd cause trouble at the dependency update step.
      its(:length) { is_expected.to eq(1) }
    end
  end
end
