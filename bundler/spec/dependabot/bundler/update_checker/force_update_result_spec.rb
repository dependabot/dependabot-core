# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/update_checker/force_update_result"
require "dependabot/bundler/update_checker/force_updater"

RSpec.describe Dependabot::Bundler::UpdateChecker::ForceUpdateResult do
  extend T::Sig

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rspec-mocks",
      version: "3.5.0",
      requirements: [{ file: "Gemfile", requirement: "~> 3.5.0", groups: [:default], source: nil }],
      package_manager: "bundler"
    )
  end

  it "retains matched dependencies and parsed versions without consuming skipped specs" do
    updates = described_class.from_helper_result(
      [
        [{ "name" => "untracked" }, { "name" => dependency.name }],
        [
          { "name" => "untracked", "version" => false },
          { "name" => dependency.name, "version" => "3.6.0" },
          { "unused" => false }
        ]
      ],
      dependencies: [dependency]
    )

    expect(updates).to contain_exactly(have_attributes(dependency: dependency, version: Gem::Version.new("3.6.0")))
  end

  it "reports a missing spec for a tracked update with helper context" do
    result = [[{ "name" => dependency.name }], []]
    expect { described_class.from_helper_result(result, dependencies: [dependency]) }.to raise_error(
      Dependabot::Bundler::UpdateChecker::ForceUpdateResult::InvalidResult, /resolved spec/
    ) do |error|
      expect(error.error_context).to include(function: "force_update")
    end
  end

  it "rejects an invalid selected version before dependency construction" do
    expect do
      described_class.from_helper_result(
        [[{ "name" => dependency.name }], [{ "name" => dependency.name, "version" => "/invalid/" }]],
        dependencies: [dependency]
      )
    end.to raise_error(Dependabot::Bundler::UpdateChecker::ForceUpdateResult::InvalidResult, /version/)
  end

  describe Dependabot::Bundler::UpdateChecker::ForceUpdater do
    sig { returns(Dependabot::Bundler::UpdateChecker::ForceUpdater) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
    let(:updater) do
      described_class.new(
        dependency: dependency,
        dependency_files: bundler_project_dependency_files("gemfile"),
        target_version: Dependabot::Bundler::Version.new("3.6.0"),
        requirements_update_strategy: Dependabot::RequirementsUpdateStrategy::BumpVersions,
        credentials: [],
        options: {}
      )
    end

    before do
      parser = instance_double(Dependabot::Bundler::FileParser, parse: [dependency])
      allow(Dependabot::Bundler::FileParser).to receive(:new).and_return(parser)
      allow(Dependabot::Bundler::NativeHelpers).to receive(:run_bundler_subprocess).and_call_original
      allow(Dependabot::Bundler::NativeHelpers).to receive(:run_bundler_subprocess)
        .with(hash_including(function: "force_update")).and_return(false)
    end

    it "does not classify a malformed helper payload as a resolution failure" do
      expect { updater.updated_dependencies }.to raise_error(
        Dependabot::Bundler::UpdateChecker::ForceUpdateResult::InvalidResult
      )
    end
  end
end
