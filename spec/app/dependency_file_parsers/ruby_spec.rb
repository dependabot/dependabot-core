require "spec_helper"
require "./app/dependency_file"
require "./app/dependency_file_parsers/ruby"

RSpec.describe DependencyFileParsers::Ruby do
  let(:files) { [gemfile] }
  let(:gemfile) { DependencyFile.new(name: "Gemfile", content: gemfile_body) }
  let(:gemfile_body) { fixture("gemfiles", "version_specified") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
      end
    end

    context "with no version specified" do
      let(:gemfile_body) { fixture("gemfiles", "version_not_specified") }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("0") }
      end
    end

    context "with a version specified as between two constraints" do
      let(:gemfile_body) { fixture("gemfiles", "version_between_bounds") }

      # TODO: For now we ignore gems with multiple requirements, because they'd
      # cause trouble at the Gemfile update step.
      its(:length) { is_expected.to eq(1) }
    end
  end
end
