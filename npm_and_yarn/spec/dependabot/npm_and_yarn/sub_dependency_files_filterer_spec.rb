# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"

RSpec.describe Dependabot::NpmAndYarn::SubDependencyFilesFilterer do
  subject(:files_requiring_update) do
    described_class.new(
      dependency_files: dependency_files,
      updated_dependencies: updated_dependencies
    ).files_requiring_update
  end

  let(:dependency_files) do
    [
      package_json,
      npm_lock,
      yarn_lock_update,
      npm_lock_update,
      npm_lock_up_to_date
    ]
  end

  let(:updated_dependencies) { [dependency] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "extend",
      version: "2.0.2",
      previous_version: nil,
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end

  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", "package.json")
    )
  end
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", "package-lock.json")
    )
  end
  let(:yarn_lock_update) do
    Dependabot::DependencyFile.new(
      name: "package/yarn.lock",
      content: fixture("yarn_lockfiles", "subdependency_in_range.lock")
    )
  end
  let(:npm_lock_update) do
    Dependabot::DependencyFile.new(
      name: "package2/package-lock.json",
      content: fixture("npm_lockfiles", "subdependency_in_range.json")
    )
  end
  let(:npm_lock_up_to_date) do
    Dependabot::DependencyFile.new(
      name: "package3/package-lock.json",
      content: fixture("npm_lockfiles",
                       "subdependency_out_of_range_gt.json")
    )
  end

  describe ".files_requiring_update" do
    it do
      is_expected.to contain_exactly(npm_lock_update, yarn_lock_update)
    end

    context "when the version is out of range" do
      let(:npm_lock_out_of_range) do
        Dependabot::DependencyFile.new(
          name: "package4/package-lock.json",
          content: fixture("npm_lockfiles",
                           "subdependency_out_of_range_lt.json")
        )
      end

      let(:dependency_files) do
        [
          package_json,
          npm_lock,
          yarn_lock_update,
          npm_lock_update,
          npm_lock_up_to_date,
          npm_lock_out_of_range
        ]
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "extend",
          version: "1.3.0",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(npm_lock_out_of_range)
      end
    end
  end
end
