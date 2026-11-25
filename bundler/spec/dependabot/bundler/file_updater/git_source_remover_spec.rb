# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/file_updater/git_source_remover"

RSpec.describe Dependabot::Bundler::FileUpdater::GitSourceRemover do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::FileUpdater::GitSourceRemover) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:remover) { described_class.new(dependency: dependency) }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "df9f605d7111b6814fe493cf8f41de3f9f0978b2",
      requirements: [],
      package_manager: "bundler"
    )
  end

  sig { returns(String) }
  let(:dependency_name) { "business" }
  # rubocop:enable RSpec/ScatteredLet

  describe "#rewrite" do
    sig { returns(String) }
    subject(:rewrite) { remover.rewrite(content) }

    sig { returns(String) }
    let(:content) do
      T.must(bundler_project_dependency_file("git_source", filename: "Gemfile").content)
    end

    context "with a dependency that specifies a ref" do
      sig { returns(String) }
      let(:dependency_name) { "business" }

      it "replaces the ref" do
        expect(rewrite).to include(%(gem "business", "~> 1.6.0"\ngem))
      end

      it "leaves other gems alone" do
        expect(rewrite).to include(%(gem "prius", git: "https))
      end
    end

    context "with non-git tags at the start" do
      sig { returns(String) }
      let(:content) do
        %(gem "business", "1.0.0", require: false, git: "git_url")
      end

      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with non-git tags at the end" do
      sig { returns(String) }
      let(:content) do
        %(gem "business", "1.0.0", git: "git_url", require: false)
      end

      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with non-git tags on a subsequent line" do
      sig { returns(String) }
      let(:content) do
        %(gem "business", "1.0.0", git: "git_url",\nrequire: false)
      end

      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with git tags on a subsequent line" do
      sig { returns(String) }
      let(:content) do
        %(gem "business", "1.0.0", require: false,\ngit: "git_url")
      end

      it { is_expected.to eq(%(gem "business", "1.0.0", require: false)) }
    end

    context "with a custom tag" do
      sig { returns(String) }
      let(:content) { %(gem "business", "1.0.0", github: "git_url") }

      it { is_expected.to eq(%(gem "business", "1.0.0")) }
    end

    context "with a comment" do
      sig { returns(String) }
      let(:content) { %(gem "business", "1.0.0", git: "git_url" # My gem) }

      it { is_expected.to eq(%(gem "business", "1.0.0" # My gem)) }
    end
  end
end
