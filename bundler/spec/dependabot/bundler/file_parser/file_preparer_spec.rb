# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_parser/file_preparer"

RSpec.describe Dependabot::Bundler::FileParser::FilePreparer do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileParser::FilePreparer) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:preparer) { described_class.new(dependency_files: dependency_files) }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { bundler_project_dependency_files("gemfile") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#prepared_dependency_files" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated Gemfile" do
      sig { returns(Dependabot::DependencyFile) }
      subject { T.must(prepared_dependency_files.find { |f| f.name == "Gemfile" }) }

      its(:content) { is_expected.to include('gem "business", "~> 1.4.0"') }
    end

    describe "the updated lockfile" do
      sig { returns(Dependabot::DependencyFile) }
      subject do
        T.must(prepared_dependency_files.find { |f| f.name == "Gemfile.lock" })
      end

      its(:content) { is_expected.to include("2.2.0") }
    end

    describe "the updated gemspec" do
      sig { returns(Dependabot::DependencyFile) }
      subject do
        T.must(prepared_dependency_files.find { |f| f.name == "example.gemspec" })
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { bundler_project_dependency_files("gemfile_gemspec_with_require") }

      its(:content) { is_expected.to include("begin\nrequire ") }
      its(:content) { is_expected.to include(%(version      = "0.0.1")) }
    end

    describe "the updated ruby version file" do
      sig { returns(Dependabot::DependencyFile) }
      subject do
        T.must(prepared_dependency_files.find { |f| f.name == ".ruby-version" })
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { bundler_project_dependency_files("ruby_version_file") }

      its(:content) { is_expected.to eq("2.2.0\n") }
    end

    describe "the updated tool versions file" do
      sig { returns(Dependabot::DependencyFile) }
      subject do
        T.must(prepared_dependency_files.find { |f| f.name == ".tool-versions" })
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { bundler_project_dependency_files("tool_versions_file") }

      its(:content) { is_expected.to eq("ruby 2.2.0\n") }
    end

    describe "the updated .specification file" do
      sig { returns(Dependabot::DependencyFile) }
      subject do
        T.must(prepared_dependency_files.find { |f| f.name == "plugins/example/.specification" })
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) { bundler_project_dependency_files("version_specified_gemfile_specification") }

      its(:content) { is_expected.to start_with("--- !ruby/object:Gem::Specification") }
    end
  end
end
