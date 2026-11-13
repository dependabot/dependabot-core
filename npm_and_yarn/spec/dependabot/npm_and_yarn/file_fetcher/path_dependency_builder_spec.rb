# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only project_name fixture in parent hooks.

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_fetcher/path_dependency_builder"

RSpec.describe Dependabot::NpmAndYarn::FileFetcher::PathDependencyBuilder do
  let(:builder) do
    described_class.new(
      dependency_name: dependency_name,
      path: path,
      directory: directory,
      package_lock: package_lock,
      yarn_lock: yarn_lock
    )
  end

  let(:dependency_name) { "etag" }
  let(:path) { "./deps/etag" }
  let(:directory) { "/" }
  let(:package_lock) { nil }
  let(:yarn_lock) { nil }

  describe "#dependency_file" do
    subject(:dependency_file) { builder.dependency_file }

    context "with an npm lockfile" do
      let(:package_lock) do
        project_dependency_files(project_name).find { |f| f.name == "package-lock.json" }
      end

      context "when dealing with a path dependency with no sub-deps" do
        let(:project_name) { "npm6/path_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to be(true)
          expect(dependency_file.content)
            .to eq('{"name":"etag","version":"0.0.1"}')
        end
      end

      context "when dealing with a path dependency with sub-deps" do
        let(:project_name) { "npm6/path_dependency_subdeps" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.support_file?).to be(true)
          expect(dependency_file.content)
            .to eq(
              {
                name: "other_package",
                version: "0.0.1",
                dependencies: { lodash: "^1.3.1" }
              }.to_json
            )
        end
      end
    end

    context "with a yarn lockfile" do
      let(:yarn_lock) do
        project_dependency_files(project_name).find { |f| f.name == "yarn.lock" }
      end

      context "when dealing with a path dependency with no sub-deps" do
        let(:project_name) { "yarn/path_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to be(true)
          expect(dependency_file.content)
            .to eq('{"name":"etag","version":"1.8.0"}')
        end
      end

      context "when dependency file can't be parsed" do
        let(:project_name) { "yarn/unparseable" }

        it "raises DependencyFileNotParseable" do
          expect { dependency_file }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "when dealing with a path dependency with sub-deps" do
        let(:project_name) { "yarn/path_dependency_subdeps" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.support_file?).to be(true)
          expect(dependency_file.content)
            .to eq(
              {
                name: "other_package",
                version: "0.0.2",
                dependencies: {
                  lodash: "^1.3.1",
                  filedep: "file:../../../correct/path/filedep"
                },
                optionalDependencies: { etag: "^1.0.0" }
              }.to_json
            )
        end
      end

      context "when dealing with a symlinked dependency" do
        let(:project_name) { "yarn/symlinked_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to be(true)
          expect(dependency_file.content)
            .to eq('{"name":"etag","version":"1.8.0"}')
        end
      end
    end

    context "with npm requirement data" do
      let(:package_lock) { Dependabot::DependencyFile.new(name: "package-lock.json", content: npm_content) }
      let(:npm_content) { { "dependencies" => { "etag" => npm_entry } }.to_json }
      let(:npm_entry) { { "version" => "file:./deps/etag", "requires" => {} } }

      it "retains an explicitly empty requirements map" do
        expect(dependency_file.content).to eq('{"name":"etag","version":"0.0.1","dependencies":{}}')
      end

      context "with invalid JSON syntax" do
        let(:npm_content) { "{" }

        it "reports the path dependency as unreachable" do
          expect { dependency_file }.to raise_error(Dependabot::PathDependenciesNotReachable)
        end
      end

      context "with a structurally invalid lockfile" do
        let(:npm_content) { "[]" }

        it "reports the malformed lockfile instead of applying syntax recovery" do
          expect { dependency_file }.to raise_error(Dependabot::DependencyFileNotParseable, /lockfile/)
        end
      end

      context "with malformed consumed requirements" do
        let(:npm_entry) { super().merge("requires" => { "child" => false }) }

        it "reports the requirements field" do
          expect { dependency_file }.to raise_error(Dependabot::DependencyFileNotParseable, /requires/)
        end
      end
    end

    context "with Yarn helper records" do
      let(:yarn_lock) { Dependabot::DependencyFile.new(name: "yarn.lock", content: "helper input") }
      let(:yarn_entry) { { "version" => "1.8.0" } }
      let(:yarn_result) { { "etag@file:./deps/etag" => yarn_entry } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "yarn:parseLockfile")).and_return(yarn_result)
      end

      it "parses the helper result once across repeated manifest reads" do
        2.times { expect(builder.dependency_file.content).to eq('{"name":"etag","version":"1.8.0"}') }
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
      end

      context "with an unused malformed npm lockfile" do
        let(:package_lock) { Dependabot::DependencyFile.new(name: "package-lock.json", content: "[]") }

        it "uses the Yarn candidate without consuming npm data" do
          expect(dependency_file.content).to eq('{"name":"etag","version":"1.8.0"}')
        end
      end

      context "when only npm has a path candidate" do
        let(:yarn_result) { { "other@^1" => { "version" => [], "dependencies" => false } } }
        let(:package_lock) do
          project_dependency_files("npm6/path_dependency").find { |f| f.name == "package-lock.json" }
        end

        it "falls back without reading unrelated Yarn fields" do
          expect(dependency_file.content).to eq('{"name":"etag","version":"0.0.1"}')
        end
      end

      context "with null and empty fields" do
        let(:yarn_entry) { { "version" => nil, "dependencies" => nil, "optionalDependencies" => {} } }

        it "defaults the version and preserves an explicit empty optional map" do
          expect(dependency_file.content).to eq('{"name":"etag","version":"0.0.1","optionalDependencies":{}}')
        end
      end

      context "with scoped nested path dependencies" do
        let(:dependency_name) { "@scope/local" }
        let(:path) { "other_package" }
        let(:yarn_result) do
          {
            "@scope/local@file:../local" => {
              "version" => "2.0.0",
              "dependencies" => { "@scope/child" => "file:/cache/child", "alias" => "npm:other@^2" },
              "optionalDependencies" => { "@scope/child" => "link:/cache/child" }
            },
            "@scope/child@file:../../correct/child" => { "version" => [] },
            "@scope/child@file:../../wrong/child" => { "version" => "1.0.0" }
          }
        end

        it "uses the first matching descriptor for both maps without reading its version" do
          expect(dependency_file.content).to eq(
            {
              name: "@scope/local",
              version: "2.0.0",
              dependencies: { "@scope/child" => "file:../../../correct/child", alias: "npm:other@^2" },
              optionalDependencies: { "@scope/child" => "file:../../../correct/child" }
            }.to_json
          )
        end
      end

      [
        ["No space left on device", Dependabot::OutOfDisk],
        ["MemoryError", Dependabot::OutOfMemory],
        ["invalid lockfile", Dependabot::DependencyFileNotParseable]
      ].each do |message, error_class|
        context "when the Yarn helper reports #{message}" do
          let(:package_lock) do
            project_dependency_files("npm6/path_dependency").find { |f| f.name == "package-lock.json" }
          end

          before do
            error = Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
            allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
              .with(hash_including(function: "yarn:parseLockfile")).and_raise(error)
          end

          it "propagates the reader's error instead of falling back to npm" do
            expect { dependency_file }.to raise_error(error_class)
          end
        end
      end
    end
  end
end
