# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#manifest_copy" do
    def bun_lock(name, workspaces, packages)
      content = { "lockfileVersion" => 1, "workspaces" => workspaces, "packages" => packages }.to_json
      Dependabot::DependencyFile.new(name: name, content: content)
    end

    def entry(version)
      ["ms@#{version}", "", {}, "sha512-example"]
    end

    def manifest_copy(manifest_name, workspace_name)
      lockfile_parser.manifest_copy(dependency_name: "ms", workspace_name: workspace_name, manifest_name: manifest_name)
    end

    before { Dependabot::Experiments.register(:enable_bun_subdependency_types, true) }

    after { Dependabot::Experiments.reset! }

    context "when a workspace has its own lockfile" do
      # packages/app/bun.lock has ms only as a devDependency. The root bun.lock also has
      # ms, and there it is a production dependency.
      let(:dependency_files) do
        [
          bun_lock("bun.lock", { "" => { "dependencies" => { "ms" => "2.1.2" } } }, { "ms" => entry("2.1.2") }),
          bun_lock(
            "packages/app/bun.lock",
            { "" => { "devDependencies" => { "ms" => "2.0.0" } } },
            { "ms" => entry("2.0.0") }
          )
        ]
      end

      it "uses the closest lockfile for both the version and the type" do
        copy = manifest_copy("packages/app/package.json", "app")

        expect(copy.details.version).to eq("2.0.0")
        expect(copy.reachable_from_production).to be(false)
      end

      it "uses the root lockfile for the root manifest" do
        copy = manifest_copy("package.json", nil)

        expect(copy.details.version).to eq("2.1.2")
        expect(copy.reachable_from_production).to be(true)
      end
    end

    context "when the closest lockfile has only the workspace's nested copy" do
      let(:dependency_files) do
        [
          bun_lock("bun.lock", { "" => { "dependencies" => { "ms" => "2.1.2" } } }, { "ms" => entry("2.1.2") }),
          bun_lock(
            "packages/app/bun.lock",
            { "" => {}, "packages/app" => { "name" => "app", "devDependencies" => { "ms" => "2.2.0" } } },
            { "app/ms" => entry("2.2.0") }
          )
        ]
      end

      it "does not fall through to a farther lockfile" do
        copy = manifest_copy("packages/app/package.json", "app")

        expect(copy.details.version).to eq("2.2.0")
        expect(copy.reachable_from_production).to be(false)
      end
    end

    context "when one lockfile has both a workspace copy and a hoisted copy" do
      let(:dependency_files) do
        [
          bun_lock(
            "bun.lock",
            {
              "" => { "devDependencies" => { "ms" => "2.0.0" } },
              "packages/app" => { "name" => "app", "dependencies" => { "ms" => "2.1.2" } }
            },
            { "ms" => entry("2.0.0"), "app/ms" => entry("2.1.2") }
          )
        ]
      end

      it "gives each manifest its own copy" do
        root_copy = manifest_copy("package.json", nil)
        app_copy = manifest_copy("packages/app/package.json", "app")

        expect([root_copy.details.version, root_copy.reachable_from_production]).to eq(["2.0.0", false])
        expect([app_copy.details.version, app_copy.reachable_from_production]).to eq(["2.1.2", true])
      end
    end

    context "when no lockfile has the dependency" do
      let(:dependency_files) { [bun_lock("bun.lock", { "" => {} }, {})] }

      it "returns nil" do
        expect(manifest_copy("package.json", nil)).to be_nil
      end
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
