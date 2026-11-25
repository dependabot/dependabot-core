# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/bundler/file_updater/gemspec_dependency_name_finder"

RSpec.describe Dependabot::Bundler::FileUpdater::GemspecDependencyNameFinder do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileUpdater::GemspecDependencyNameFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:finder) { described_class.new(gemspec_content: gemspec_content) }
  sig { returns(String) }
  let(:gemspec_content) do
    T.must(bundler_project_dependency_file("gemfile_small_example", filename: "example.gemspec").content)
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#dependency_name" do
    sig { returns(T.nilable(String)) }
    subject(:dependency_name) { finder.dependency_name }

    it { is_expected.to eq("example") }

    context "with an unevaluatable gemspec name" do
      sig { returns(String) }
      let(:gemspec_content) do
        T.must(bundler_project_dependency_file("gemfile_function_name", filename: "example.gemspec").content)
      end

      it { is_expected.to be_nil }
    end
  end
end
