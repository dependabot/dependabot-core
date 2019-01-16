# frozen_string_literal: true

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
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:yarn_lock) { nil }

  let(:npm_lock_fixture_name) { "path_dependency.json" }

  describe "#dependency_file" do
    subject(:dependency_file) { builder.dependency_file }

    context "with an npm lockfile" do
      let(:package_lock) do
        Dependabot::DependencyFile.new(
          name: "package-lock.json",
          content: fixture("npm_lockfiles", npm_lock_fixture_name)
        )
      end
      let(:npm_lock_fixture_name) { "path_dependency.json" }

      context "for a path dependency with no sub-deps" do
        let(:npm_lock_fixture_name) { "path_dependency.json" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.type).to eq("path_dependency")
          expect(dependency_file.content).
            to eq("{\"name\":\"etag\",\"version\":\"0.0.1\"}")
        end
      end

      context "for a path dependency with sub-deps" do
        let(:npm_lock_fixture_name) { "path_dependency_subdeps.json" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.type).to eq("path_dependency")
          expect(dependency_file.content).
            to eq({
              name: "other_package",
              version: "0.0.1",
              dependencies: { lodash: "^1.3.1" }
            }.to_json)
        end
      end
    end

    context "with a yarn lockfile" do
      let(:package_lock) { nil }
      let(:yarn_lock) do
        Dependabot::DependencyFile.new(
          name: "yarn.lock",
          content:
            fixture("yarn_lockfiles", yarn_lock_fixture_name)
        )
      end
      let(:yarn_lock_fixture_name) { "path_dependency.json" }

      context "for a path dependency with no sub-deps" do
        let(:yarn_lock_fixture_name) { "path_dependency.lock" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.type).to eq("path_dependency")
          expect(dependency_file.content).
            to eq("{\"name\":\"etag\",\"version\":\"1.8.0\"}")
        end
      end

      context "for a path dependency with sub-deps" do
        let(:yarn_lock_fixture_name) { "path_dependency_subdeps.lock" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.type).to eq("path_dependency")
          expect(dependency_file.content).
            to eq({
              name: "other_package",
              version: "0.0.2",
              dependencies: {
                lodash: "^1.3.1",
                filedep: "file:../../../correct/path/filedep"
              },
              optionalDependencies: { etag: "^1.0.0" }
            }.to_json)
        end
      end
    end
  end
end
