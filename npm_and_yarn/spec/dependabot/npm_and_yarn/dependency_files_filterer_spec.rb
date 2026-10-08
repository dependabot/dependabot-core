# typed: false
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

  describe "workspace manifest reads" do
    let(:workspaces) { [] }
    let(:root_manifest) do
      Dependabot::DependencyFile.new(
        name: "package.json",
        content: JSON.dump("workspaces" => workspaces, "dependencies" => [])
      )
    end
    let(:member_manifest) do
      Dependabot::DependencyFile.new(name: "packages/member/package.json", content: "{}")
    end
    let(:root_lockfile) { Dependabot::DependencyFile.new(name: "package-lock.json", content: "{}") }
    let(:dependency_files) { [root_manifest, member_manifest, root_lockfile] }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "chalk",
        version: "0.4.0",
        requirements: [{
          file: member_manifest.name,
          requirement: "0.3.0",
          groups: ["dependencies"],
          source: nil
        }],
        package_manager: "npm_and_yarn"
      )
    end

    before do
      lockfile_parser = instance_double(Dependabot::NpmAndYarn::FileParser::LockfileParser, parse: [dependency])
      allow(Dependabot::NpmAndYarn::FileParser::LockfileParser).to receive(:new).and_return(lockfile_parser)
    end

    it "keeps the workspace lockfile without inspecting unrelated manifest fields" do
      expect(files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
    end

    context "with an object workspace declaration" do
      let(:workspaces) { {} }

      it "keeps the root lockfile" do
        expect(files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
      end
    end

    [nil, false].each do |value|
      context "with workspaces set to #{value.inspect}" do
        let(:workspaces) { value }

        it "does not treat the root lockfile as a workspace lockfile" do
          expect(files_requiring_update).to eq([member_manifest])
        end
      end
    end

    context "with a pnpm workspace file instead of a workspace declaration" do
      let(:workspaces) { nil }
      let(:dependency_files) do
        super() + [Dependabot::DependencyFile.new(name: "pnpm-workspace.yaml", content: "packages: []")]
      end

      it "retains the pnpm workspace fallback" do
        expect(files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
      end
    end

    context "when the nested package has its own lockfile and no root manifest" do
      let(:root_lockfile) do
        Dependabot::DependencyFile.new(name: "packages/member/package-lock.json", content: "{}")
      end
      let(:dependency_files) { [member_manifest, root_lockfile] }

      it "does not attempt to read the root manifest" do
        expect(files_requiring_update).to contain_exactly(member_manifest, root_lockfile)
      end
    end

    context "with multiple workspace lockfiles" do
      let(:other_lockfile) { Dependabot::DependencyFile.new(name: "yarn.lock", content: "") }
      let(:dependency_files) { super() + [other_lockfile] }

      it "decodes the root manifest once" do
        allow(JSON).to receive(:parse).and_call_original

        expect(files_requiring_update).to contain_exactly(member_manifest, root_lockfile, other_lockfile)
        expect(JSON).to have_received(:parse).with(root_manifest.content).once
      end
    end
  end

  describe ".files_requiring_update" do
    it do
      expect(files_requiring_update).to contain_exactly(
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
        expect(files_requiring_update).to contain_exactly(
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
        expect(files_requiring_update).to contain_exactly(
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
          expect(files_requiring_update).to contain_exactly(
            project_dependency_file("package-lock.json"),
            project_dependency_file("packages/package1/package.json")
          )
        end
      end
    end

    context "when using npm workspaces with a shrinkwrap" do
      let(:project_name) { "npm8/workspaces_shrinkwrap" }
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
        expect(files_requiring_update).to contain_exactly(
          project_dependency_file("npm-shrinkwrap.json"),
          project_dependency_file("packages/package1/package.json")
        )
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
        expect(files_requiring_update).to contain_exactly(
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
        expect(files_requiring_update).to contain_exactly(
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

  describe ".paths_requiring_update_check" do
    subject(:paths_requiring_update_check) do
      described_class.new(
        dependency_files: dependency_files,
        updated_dependencies: updated_dependencies
      ).paths_requiring_update_check
    end

    it do
      expect(paths_requiring_update_check).to contain_exactly(
        "."
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
        expect(paths_requiring_update_check).to contain_exactly(
          "packages/package2"
        )
      end
    end
  end
end
