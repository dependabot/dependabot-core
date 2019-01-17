# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/dependency_files_filterer"

RSpec.describe Dependabot::NpmAndYarn::DependencyFilesFilterer do
  subject(:filtered_files) do
    described_class.new(
      dependency_files: dependency_files,
      dependencies: dependencies
    ).filtered_files
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

  let(:dependencies) { [dependency] }

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

  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: "{}"
    )
  end
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: "{}"
    )
  end
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: "{}"
    )
  end
  let(:nested_package_json) do
    Dependabot::DependencyFile.new(
      name: "helpers/package.json",
      content: "{}"
    )
  end
  let(:nested_shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "helpers/npm-shrinkwrap.json",
      content: "{}"
    )
  end

  describe ".filtered_files" do
    it do
      is_expected.to contain_exactly(package_json, yarn_lock, npm_lock)
    end

    context "with no requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          package_json,
          yarn_lock,
          npm_lock
        )
      end
    end

    context "with a nested dependency requirement" do
      let(:dependencies) { [nested_dependency] }

      let(:nested_dependency) do
        Dependabot::Dependency.new(
          name: "react",
          version: "16.7.0",
          requirements: [{
            file: "helpers/package.json",
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
        let(:dependencies) { [dependency, other_dependency] }

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
    end
  end

  describe ".filtered_package_files" do
    subject(:filtered_package_files) do
      described_class.new(
        dependency_files: dependency_files,
        dependencies: dependencies
      ).filtered_package_files
    end

    it do
      is_expected.to contain_exactly(package_json)
    end
  end

  describe ".filtered_lockfiles" do
    subject(:filtered_lockfiles) do
      described_class.new(
        dependency_files: dependency_files,
        dependencies: dependencies
      ).filtered_lockfiles
    end

    it do
      is_expected.to contain_exactly(yarn_lock, npm_lock)
    end
  end
end
