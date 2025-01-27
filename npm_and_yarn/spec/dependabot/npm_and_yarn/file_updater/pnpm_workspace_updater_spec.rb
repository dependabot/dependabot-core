# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_updater/pnpm_workspace_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::PnpmWorkspaceUpdater do
  let(:pnpm_workspace_updater) do
    described_class.new(
      workspace_file: workspace_file,
      dependencies: dependencies
    )
  end

  let(:workspace_file) do
    project_dependency_files(project_name).find { |f| f.name == "pnpm-workspace.yaml" }
  end

  let(:project_name) { "pnpm/catalog_prettier" }

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "prettier",
      version: "3.3.0",
      package_manager: "npm_and_yarn",
      requirements: [{
        file: "pnpm-workspace.yaml",
        requirement: "3.3.3",
        groups: ["dependencies"],
        source: nil
      }],
      previous_requirements: [{
        file: "pnpm-workspace.yaml",
        requirement: "3.3.0",
        groups: ["dependencies"],
        source: nil
      }]
    )
  end

  describe "#updated_pnmp_workspace" do
    subject(:updated_package_json) { pnpm_workspace_updater.updated_pnpm_workspace }

    its(:content) { is_expected.to include "prettier: 3.3.3" }

    context("with multiple dependencies") do
      let(:project_name) { "pnpm/catalog_multiple" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "prettier",
            version: "3.3.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^3.3.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^3.3.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "left-pad",
            version: "1.0.1",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^1.0.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^1.0.1",
              groups: [],
              source: nil
            }]
          )
        ]
      end

      its(:content) { is_expected.to include "prettier: ^3.3.3" }
      its(:content) { is_expected.to include "left-pad: ^1.0.3" }
    end

    context("with catalog group dependency") do
      let(:project_name) { "pnpm/catalogs_react" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "react",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          )
        ]
      end

      its(:content) { is_expected.to include "react: ^18.2.3" }
      its(:content) { is_expected.to include "react-dom: ^18.2.3" }
    end

    context("with catalog group dependency") do
      let(:project_name) { "pnpm/catalogs_multiple_reacts" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "react",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react",
            version: "16.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^16.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^16.0.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "16.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^16.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^16.0.0",
              groups: [],
              source: nil
            }]
          )
        ]
      end

      its(:content) { is_expected.to include "react: ^18.2.3" }
      its(:content) { is_expected.to include "react-dom: ^18.2.3" }

      its(:content) { is_expected.to include "react: ^16.2.3" }
      its(:content) { is_expected.to include "react-dom: ^16.2.3" }
    end

    context("with catalog and catalog groups with valid yaml") do
      let(:project_name) { "pnpm/catalogs_valid_yaml" }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "prettier",
            version: "3.3.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "3.3.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "3.3.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "express",
            version: "4.15.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "4.21.2",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "4.15.2",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "is-even",
            version: "0.1.2",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "1.0.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "0.1.2",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          ),
          Dependabot::Dependency.new(
            name: "react-dom",
            version: "18.0.0",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.2.3",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "pnpm-workspace.yaml",
              requirement: "^18.0.0",
              groups: [],
              source: nil
            }]
          )
        ]
      end

      its(:content) { is_expected.to include "prettier: \"3.3.3\"" }
      its(:content) { is_expected.to include "\"express\": 4.21.2" }
      its(:content) { is_expected.to include "is-even: '1.0.0'" }

      its(:content) { is_expected.to include "react: \"^18.2.3\"" }
      its(:content) { is_expected.to include "react-dom: '^18.2.3'" }
    end
  end
end
