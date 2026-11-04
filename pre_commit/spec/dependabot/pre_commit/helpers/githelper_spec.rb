# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pre_commit/helpers"

RSpec.describe Dependabot::PreCommit::Helpers::Githelper do
  extend T::Sig

  sig { returns(Dependabot::PreCommit::Helpers::Githelper) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:git_helper) do
    described_class.new(
      dependency: dependency,
      credentials: [],
      dependency_source_details: fallback_source,
      consider_version_branches_pinned: false
    )
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(T::Hash[Symbol, Object]) }
  let(:source) do
    {
      type: "git",
      url: "https://github.com/pre-commit/pre-commit-hooks",
      ref: "v4.4.0",
      branch: nil
    }
  end
  sig { returns(T::Hash[Symbol, Object]) }
  let(:fallback_source) do
    {
      type: "git",
      url: "https://github.com/pre-commit/pre-commit-hooks",
      ref: "fallback",
      branch: "main"
    }
  end
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "https://github.com/pre-commit/pre-commit-hooks",
      version: "4.4.0",
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".pre-commit-config.yaml",
        source: source
      }],
      package_manager: "pre_commit"
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  describe "#git_commit_checker_for" do
    it "parses source details" do
      checker = git_helper.git_commit_checker_for(source)

      expect(checker.dependency_source_details).to have_attributes(
        type: "git",
        url: "https://github.com/pre-commit/pre-commit-hooks",
        ref: "v4.4.0",
        branch: nil
      )
    end

    it "ignores unknown source metadata" do
      source_with_metadata = source.merge(metadata: { comment: "# frozen: v4.4.0" })
      checker = git_helper.git_commit_checker_for(source_with_metadata)

      expect(checker.dependency_source_details).to have_attributes(
        type: "git",
        url: "https://github.com/pre-commit/pre-commit-hooks",
        ref: "v4.4.0",
        branch: nil
      )
    end
  end
end
