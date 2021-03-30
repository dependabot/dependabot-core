# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_parser/file_preparer"

RSpec.describe Dependabot::Bundler::FileParser::FilePreparer do
  let(:preparer) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { bundler_project_dependency_files("gemfile") }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated Gemfile" do
      subject { prepared_dependency_files.find { |f| f.name == "Gemfile" } }
      its(:content) { is_expected.to include('gem "business", "~> 1.4.0"') }
    end

    describe "the updated lockfile", :bundler_v1_only do
      subject do
        prepared_dependency_files.find { |f| f.name == "Gemfile.lock" }
      end

      its(:content) { is_expected.to include("1.10.6") }
    end

    describe "the updated lockfile", :bundler_v2_only do
      subject do
        prepared_dependency_files.find { |f| f.name == "Gemfile.lock" }
      end

      its(:content) { is_expected.to include("2.2.0") }
    end

    describe "the updated gemspec" do
      subject do
        prepared_dependency_files.find { |f| f.name == "example.gemspec" }
      end

      let(:dependency_files) { bundler_project_dependency_files("gemfile_gemspec_with_require") }

      its(:content) { is_expected.to include("begin\nrequire ") }
      its(:content) { is_expected.to include(%(version      = "0.0.1")) }
    end

    describe "the updated ruby version file" do
      subject do
        prepared_dependency_files.find { |f| f.name == ".ruby-version" }
      end

      let(:dependency_files) { bundler_project_dependency_files("ruby_version_file") }

      its(:content) { is_expected.to eq("2.2.0\n") }
    end

    describe "the updated .specification file" do
      subject do
        prepared_dependency_files.find { |f| f.name == "plugins/example/.specification" }
      end

      let(:dependency_files) { bundler_project_dependency_files("version_specified_gemfile_specification") }

      its(:content) { is_expected.to start_with("--- !ruby/object:Gem::Specification") }
    end
  end
end
