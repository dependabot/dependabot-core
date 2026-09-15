# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#reachable_from_production?" do
    # packages/app has its own bun.lock, where ms is only a devDependency.
    # The root bun.lock also has ms, and there it is a production dependency.
    let(:dependency_files) do
      [
        bun_lock("bun.lock", "dependencies" => { "ms" => "2.1.2" }),
        bun_lock("packages/app/bun.lock", "devDependencies" => { "ms" => "2.1.2" })
      ]
    end

    def bun_lock(name, root_workspace)
      content = {
        "lockfileVersion" => 1,
        "workspaces" => { "" => root_workspace },
        "packages" => { "ms" => ["ms@2.1.2", "", {}, "sha512-example"] }
      }.to_json
      Dependabot::DependencyFile.new(name: name, content: content)
    end

    def reachable_from_production?(manifest_name, workspace_name)
      lockfile_parser.reachable_from_production?(
        dependency_name: "ms",
        workspace_name: workspace_name,
        manifest_name: manifest_name
      )
    end

    before { Dependabot::Experiments.register(:enable_bun_subdependency_types, true) }

    after { Dependabot::Experiments.reset! }

    it "reads the closest lockfile that has the dependency, not a farther one" do
      expect(reachable_from_production?("packages/app/package.json", "app")).to be(false)
    end

    it "reads the root lockfile for the root manifest" do
      expect(reachable_from_production?("package.json", nil)).to be(true)
    end
  end

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "when dealing with bun.lock" do
      context "when the lockfile is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to eq("Invalid bun.lock file: malformed JSONC at line 3, column 1")
            end
        end
      end

      context "when the lockfile version is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile_version") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to include("lockfileVersion")
            end
        end
      end

      context "when the lockfile version is newer than the bundled bun supports" do
        let(:dependency_files) { project_dependency_files("bun/unsupported_lockfile_version") }

        it "raises a DependencyFileNotSupported error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotSupported) do |error|
              expect(error.message).to include("Unsupported bun.lock 'lockfileVersion' 2")
              expect(error.message).to include(
                "supports up to #{Dependabot::Bun::BunPackageManager::MAX_SUPPORTED_LOCKFILE_VERSION}"
              )
            end
        end
      end

      context "when the configVersion is invalid" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "package.json",
              content: '{"dependencies": {"etag": "^1.0.0"}}'
            ),
            Dependabot::DependencyFile.new(
              name: "bun.lock",
              content: '{"lockfileVersion": 0, "configVersion": "invalid", "workspaces": {}, "packages": {}}'
            )
          ]
        end

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to include("configVersion")
            end
        end
      end

      context "when dealing with v0 format" do
        context "with a simple project" do
          let(:dependency_files) { project_dependency_files("bun/simple_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
              name: "fetch-factory",
              version: "0.0.1"
            )
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.length).to eq(11)
          end
        end

        context "with a simple workspace project" do
          let(:dependency_files) { project_dependency_files("bun/simple_workspace_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.find { |d| d.name == "lodash" }).to have_attributes(
              name: "lodash",
              version: "1.3.1"
            )
            expect(dependencies.find { |d| d.name == "chalk" }).to have_attributes(
              name: "chalk",
              version: "0.3.0"
            )
            expect(dependencies.length).to eq(5)
          end
        end
      end

      context "when dealing with v1 format" do
        let(:dependency_files) { project_dependency_files("bun/simple_v1") }

        it "parses dependencies properly" do
          expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
            name: "fetch-factory",
            version: "0.0.1"
          )
          expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
            name: "etag",
            version: "1.8.1"
          )
          expect(dependencies.length).to eq(17)
        end
      end

      context "when the lockfile has configVersion" do
        context "with configVersion: 0" do
          let(:dependency_files) { project_dependency_files("bun/simple_v0_with_config_version") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
              name: "fetch-factory",
              version: "0.0.1"
            )
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.length).to eq(11)
          end
        end
      end
    end
  end
end
