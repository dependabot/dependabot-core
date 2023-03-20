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
    project_dependency_files(project_name)
  end
  let(:project_name) { "npm6_and_yarn/simple" }
  let(:updated_dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "fetch-factory",
      version: "0.0.2",
      requirements: [{
        file: "package.json",
        requirement: "^0.0.1",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "npm_and_yarn"
    )
  end

  def project_dependency_file(file_name)
    dependency_files.find { |f| f.name == file_name }
  end

  describe ".files_requiring_update" do
    it do
      is_expected.to contain_exactly(
        project_dependency_file("package.json"),
        project_dependency_file("package-lock.json"),
        project_dependency_file("yarn.lock")
      )
    end

    context "with a nested dependency requirement" do
      let(:project_name) { "npm6_and_yarn/nested_dependency_update" }
      let(:updated_dependencies) { [nested_dependency] }
      let(:nested_dependency) do
        Dependabot::Dependency.new(
          name: "objnest",
          version: "4.1.2",
          requirements: [{
            file: "packages/package2/package.json",
            requirement: "^4.1.2",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          project_dependency_file("packages/package2/package.json"),
          project_dependency_file("packages/package2/package-lock.json")
        )
      end
    end

    context "when using npm workspaces" do
      let(:project_name) { "npm8/workspaces" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "1.3.0",
          requirements: [{
            file: "package.json",
            requirement: "1.2.0",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          project_dependency_file("package.json"),
          project_dependency_file("package-lock.json")
        )
      end

      context "with a nested dependency requirement" do
        let(:updated_dependencies) { [nested_dependency] }
        let(:nested_dependency) do
          Dependabot::Dependency.new(
            name: "chalk",
            version: "0.4.0",
            requirements: [{
              file: "packages/package1/package.json",
              requirement: "0.3.0",
              groups: ["dependencies"],
              source: nil
            }],
            package_manager: "npm_and_yarn"
          )
        end

        it do
          is_expected.to contain_exactly(
            project_dependency_file("package-lock.json"),
            project_dependency_file("packages/package1/package.json")
          )
        end
      end
    end

    context "when using yarn workspaces" do
      let(:project_name) { "yarn/workspaces" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.8.1",
          requirements: [{
            file: "other_package/package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }, {
            file: "packages/package1/package.json",
            requirement: "^1.1.0",
            groups: ["devDependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          project_dependency_file("yarn.lock"),
          project_dependency_file("other_package/package.json"),
          project_dependency_file("packages/package1/package.json")
        )
      end
    end

    context "with multiple dependencies" do
      let(:project_name) { "npm6_and_yarn/nested_dependency_update" }
      let(:updated_dependencies) { [dependency, other_dependency] }
      let(:other_dependency) do
        Dependabot::Dependency.new(
          name: "polling-to-event",
          version: "2.1.0",
          requirements: [{
            file: "packages/package1/package.json",
            requirement: "^2.1.0",
            groups: ["dependencies"],
            source: nil
          }, {
            file: "packages/package3/package.json",
            requirement: "^2.1.0",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          # fetch-factory:
          project_dependency_file("package.json"),
          project_dependency_file("yarn.lock"),
          project_dependency_file("package-lock.json"),
          # polling-to-event:
          project_dependency_file("packages/package1/package.json"),
          project_dependency_file("packages/package1/package-lock.json"),
          project_dependency_file("packages/package3/package.json"),
          project_dependency_file("packages/package3/yarn.lock")
        )
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
      is_expected.to contain_exactly(
        project_dependency_file("package.json")
      )
    end

    context "with a nested dependency requirement" do
      let(:project_name) { "npm6_and_yarn/nested_dependency_update" }
      let(:updated_dependencies) { [nested_dependency] }
      let(:nested_dependency) do
        Dependabot::Dependency.new(
          name: "objnest",
          version: "4.1.2",
          requirements: [{
            file: "packages/package2/package.json",
            requirement: "^4.1.2",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        is_expected.to contain_exactly(
          project_dependency_file("packages/package2/package.json")
        )
      end
    end
  end
end
