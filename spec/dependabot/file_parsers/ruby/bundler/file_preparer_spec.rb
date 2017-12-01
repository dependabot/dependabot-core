# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/file_parsers/ruby/bundler/file_preparer"

RSpec.describe Dependabot::FileParsers::Ruby::Bundler::FilePreparer do
  let(:preparer) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [gemfile, lockfile] }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated Gemfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Gemfile" } }
      its(:content) { is_expected.to eq(gemfile.content) }
    end

    describe "the updated lockfile" do
      subject do
        prepared_dependency_files.find { |f| f.name == "Gemfile.lock" }
      end

      its(:content) { is_expected.to eq(lockfile.content) }
    end

    describe "the updated gemspec" do
      subject do
        prepared_dependency_files.find { |f| f.name == "example.gemspec" }
      end

      let(:dependency_files) { [gemfile, lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemspecs", "with_require"),
          name: "example.gemspec"
        )
      end

      its(:content) { is_expected.to_not include("require ") }
      its(:content) { is_expected.to include(%(version      = "0.0.1")) }
    end

    describe "the updated ruby version file" do
      subject do
        prepared_dependency_files.find { |f| f.name == ".ruby-version" }
      end

      let(:dependency_files) { [gemfile, lockfile, ruby_version] }
      let(:ruby_version) do
        Dependabot::DependencyFile.new(
          content: "2.4.1",
          name: ".ruby-version"
        )
      end

      its(:content) { is_expected.to eq(ruby_version.content) }
    end
  end
end
