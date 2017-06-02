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
      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
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
      # they'd cause trouble at the dependency update step.
      its(:length) { is_expected.to eq(1) }
    end
  end

  describe Dependabot::FileParsers::Python::Pip::LineParser do
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
