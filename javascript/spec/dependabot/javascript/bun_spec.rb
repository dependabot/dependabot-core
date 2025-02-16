# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Javascript::Bun do
  extend T::Sig

  describe "ecosystem setup" do
    it "has the correct ecosystem name" do
      expect(described_class::ECOSYSTEM).to eq("bun")
    end
  end

  describe "dependency registrations" do
    it "registers the bun ecosystem with required components" do
      fetcher = T.let(
        Dependabot::FileFetchers.for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::FileFetcher)
      )
      expect(fetcher).to eq(Dependabot::Javascript::Bun::FileFetcher)

      parser = T.let(
        Dependabot::FileParsers.for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::FileParser)
      )
      expect(parser).to eq(Dependabot::Javascript::Bun::FileParser)

      updater = T.let(
        Dependabot::FileUpdaters.for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::FileUpdater)
      )
      expect(updater).to eq(Dependabot::Javascript::Bun::FileUpdater)

      checker = T.let(
        Dependabot::UpdateCheckers.for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::UpdateChecker)
      )
      expect(checker).to eq(Dependabot::Javascript::Bun::UpdateChecker)

      finder = T.let(
        Dependabot::MetadataFinders.for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Shared::MetadataFinder)
      )
      expect(finder).to eq(Dependabot::Javascript::Shared::MetadataFinder)
    end

    it "registers the correct requirement and version classes" do
      requirement_class = T.let(
        Dependabot::Utils.requirement_class_for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::Requirement)
      )
      expect(requirement_class).to eq(Dependabot::Javascript::Bun::Requirement)

      version_class = T.let(
        Dependabot::Utils.version_class_for_package_manager("bun"),
        T.class_of(Dependabot::Javascript::Bun::Version)
      )
      expect(version_class).to eq(Dependabot::Javascript::Bun::Version)
    end
  end

  describe "pull request labeling" do
    it "registers the correct label details" do
      label_details = T.let(
        Dependabot::PullRequestCreator::Labeler
          .label_details_for_package_manager("bun"),
        T::Hash[Symbol, String]
      )
      expect(label_details).to eq(name: "javascript", colour: "168700")
    end
  end

  describe "production dependency check" do
    it "considers all dependencies as production dependencies" do
      checker = T.let(
        Dependabot::Dependency.production_check_for_package_manager("bun"),
        T.proc.params(arg0: T.untyped).returns(T::Boolean)
      )
      expect(checker.call(nil)).to be true
    end
  end
end
