# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/prek"

RSpec.describe Dependabot::Prek do
  it "registers the file fetcher" do
    expect(Dependabot::FileFetchers.for_package_manager("prek"))
      .to eq(Dependabot::Prek::FileFetcher)
  end

  it "registers the file parser" do
    expect(Dependabot::FileParsers.for_package_manager("prek"))
      .to eq(Dependabot::Prek::FileParser)
  end

  it "registers the update checker" do
    expect(Dependabot::UpdateCheckers.for_package_manager("prek"))
      .to eq(Dependabot::Prek::UpdateChecker)
  end

  it "registers the file updater" do
    expect(Dependabot::FileUpdaters.for_package_manager("prek"))
      .to eq(Dependabot::Prek::FileUpdater)
  end

  it "registers the metadata finder" do
    expect(Dependabot::MetadataFinders.for_package_manager("prek"))
      .to eq(Dependabot::Prek::MetadataFinder)
  end

  it "registers the version class" do
    expect(Dependabot::Utils.version_class_for_package_manager("prek"))
      .to eq(Dependabot::Prek::Version)
  end

  it "registers the requirement class" do
    expect(Dependabot::Utils.requirement_class_for_package_manager("prek"))
      .to eq(Dependabot::Prek::Requirement)
  end

  it "registers a production check" do
    expect(Dependabot::Dependency.production_check_for_package_manager("prek"))
      .to respond_to(:call)
  end

  it "registers a PR labeler colour" do
    expect(Dependabot::PullRequestCreator::Labeler.label_details_for_package_manager("prek"))
      .to include(name: "prek")
  end

  describe "humanized_previous_version_builder registration" do
    subject(:humanized_previous_version) { dependency.humanized_previous_version }

    context "when a frozen SHA-pinned repo carries a version comment" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "https://github.com/pre-commit/pre-commit-hooks",
          version: "10864545ddc58bd96330029b6bff16da3d072237",
          previous_version: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e",
          requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "10864545ddc58bd96330029b6bff16da3d072237", branch: nil
            },
            metadata: { comment_version: "v4.4.0", new_comment_version: "v6.0.0" }
          }],
          previous_requirements: [{
            requirement: nil, groups: [], file: "prek.toml",
            source: {
              type: "git", url: "https://github.com/pre-commit/pre-commit-hooks",
              ref: "6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e", branch: nil
            },
            metadata: { comment: "# frozen: v4.4.0" }
          }],
          package_manager: "prek"
        )
      end

      it "returns the version from the comment instead of the SHA" do
        expect(humanized_previous_version).to eq("v4.4.0")
      end
    end
  end
end
