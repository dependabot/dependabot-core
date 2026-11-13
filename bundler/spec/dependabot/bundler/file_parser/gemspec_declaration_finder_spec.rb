# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/file_parser/gemspec_declaration_finder"

RSpec.describe Dependabot::Bundler::FileParser::GemspecDeclarationFinder do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileParser::GemspecDeclarationFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:checker) do
    described_class.new(gemspec: gemspec)
  end

  sig { returns(String) }
  let(:dependency_name) { "business" }

  sig { returns(Dependabot::DependencyFile) }
  let(:gemspec) { bundler_project_dependency_file("gemspec_loads_another", filename: "example.gemspec") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#gemspec_includes_dependency?" do
    sig { returns(T::Boolean) }
    subject(:gemspec_includes_dependency) do
      checker.gemspec_includes_dependency?(dependency_name)
    end

    context "when the file does not include the dependency" do
      sig { returns(String) }
      let(:dependency_name) { "dependabot-core" }

      it { is_expected.to be(false) }
    end

    context "when the file does include the dependency as `add_dependency`" do
      sig { returns(String) }
      let(:dependency_name) { "excon" }

      it { is_expected.to be(true) }
    end

    context "when the file does include the dependency as `add_runtime_dependency`" do
      sig { returns(String) }
      let(:dependency_name) { "bundler" }

      it { is_expected.to be(true) }
    end

    context "when the file does include the dependency as `add_development_dependency`" do
      sig { returns(String) }
      let(:dependency_name) { "webmock" }

      it { is_expected.to be(true) }
    end

    context "when the file loads the dependency dynamically" do
      sig { returns(String) }
      let(:dependency_name) { "rake" }

      it { is_expected.to be(false) }
    end
  end
end
