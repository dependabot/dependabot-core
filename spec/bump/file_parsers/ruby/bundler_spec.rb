# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/file_parsers/ruby/bundler"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Bump::FileParsers::Ruby::Bundler do
  it_behaves_like "a dependency file parser"

  let(:files) { [gemfile, lockfile] }
  let(:gemfile) do
    Bump::DependencyFile.new(name: "Gemfile", content: gemfile_content)
  end
  let(:lockfile) do
    Bump::DependencyFile.new(name: "Gemfile.lock", content: lockfile_content)
  end
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:gemfile_content) { fixture("ruby", "gemfiles", "version_specified") }
      let(:lockfile_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
      end
    end

    context "with no version specified" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "version_not_specified")
      end
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "version_not_specified.lock")
      end

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("business") }
        its(:version) { is_expected.to eq("1.4.0") }
      end
    end

    context "with a version specified as between two constraints" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "version_between_bounds")
      end
      let(:lockfile_content) { fixture("ruby", "lockfiles", "Gemfile.lock") }

      its(:length) { is_expected.to eq(1) }
    end

    context "with development dependencies" do
      let(:gemfile_content) do
        fixture("ruby", "gemfiles", "development_dependencies")
      end
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "development_dependencies.lock")
      end

      its(:length) { is_expected.to eq(2) }
    end

    context "with a dependency that doesn't appear in the lockfile" do
      let(:gemfile_content) { fixture("ruby", "gemfiles", "platform_windows") }
      let(:lockfile_content) do
        fixture("ruby", "lockfiles", "platform_windows.lock")
      end

      its(:length) { is_expected.to eq(1) }
    end
  end
end
