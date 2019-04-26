# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/dependency_files_filterer"

RSpec.describe Dependabot::NpmAndYarn::DependencyFilesFilterer do
  subject(:files_requiring_update) do
    described_class.new(
      dependency_files: dependency_files,
      updated_dependencies: updated_dependencies
    ).files_requiring_update
  end

  let(:dependency_files) do
    [
      package_json,
      yarn_lock,
      npm_lock,
      nested_package_json,
      nested_shrinkwrap
    ]
  end

  let(:updated_dependencies) { [dependency] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "etag",
      version: "1.0.0",
      requirements: [{
        file: "package.json",
        requirement: "^1.0.0",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "npm_and_yarn"
    )
  end
  let(:nested_dependency) do
    Dependabot::Dependency.new(
      name: "chalk",
      version: "3.10.1",
      requirements: [{
        file: "packages/package1/package.json",
        requirement: "^3.10.1",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "npm_and_yarn"
    )
  end

  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", "package.json")
    )
  end
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("yarn_lockfiles", "yarn.lock")
    )
  end
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", "package-lock.json")
    )
  end
  let(:nested_package_json) do
    Dependabot::DependencyFile.new(
      name: "packages/package1/package.json",
      content: fixture("package_files", "package1.json")
    )
  end
  let(:nested_shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "packages/package1/npm-shrinkwrap.json",
      content: fixture("shrinkwraps", "npm-shrinkwrap.json")
    )
  end

  describe ".files_requiring_update" do
    it do
      is_expected.to contain_exactly(package_json, yarn_lock, npm_lock)
    end

    context "with a nested dependency requirement" do
      let(:updated_dependencies) { [nested_dependency] }

      it do
        is_expected.to contain_exactly(
          nested_package_json,
          nested_shrinkwrap
        )
      end

      context "with multiple dependencies" do
        let(:dependency_files) do
          [
            package_json,
            yarn_lock,
            npm_lock,
            other_package_json,
            nested_package_json,
            nested_shrinkwrap
          ]
        end
        let(:updated_dependencies) { [dependency, other_dependency] }

        let(:other_package_json) do
          Dependabot::DependencyFile.new(
            name: "other/package.json",
            content: "{}"
          )
        end

        let(:other_dependency) do
          Dependabot::Dependency.new(
            name: "react",
            version: "16.7.0",
            requirements: [{
              file: "other/package.json",
              requirement: "^16.7.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it do
          is_expected.to contain_exactly(
            package_json,
            yarn_lock,
            npm_lock,
            other_package_json
          )
        end
      end

      context "when using yarn workspaces" do
        let(:package_json) do
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: fixture("package_files", "workspaces.json")
          )
        end
        let(:yarn_lock) do
          Dependabot::DependencyFile.new(
            name: "yarn.lock",
            content: fixture("yarn_lockfiles", "workspaces.lock")
          )
        end

        it do
          is_expected.to contain_exactly(
            yarn_lock,
            nested_package_json,
            nested_shrinkwrap
          )
        end
      end
    end
  end

  describe ".package_files_requiring_update" do
    subject(:package_files_requiring_update) do
      described_class.new(
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies
      ).package_files_requiring_update
    end

    it do
      is_expected.to contain_exactly(package_json)
    end

    context "with a nested dependency requirement" do
      let(:updated_dependencies) { [nested_dependency] }

      it do
        is_expected.to contain_exactly(
          nested_package_json
        )
      end
    end
  end
end
