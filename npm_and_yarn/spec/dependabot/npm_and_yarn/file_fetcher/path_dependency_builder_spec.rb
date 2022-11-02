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
  let(:package_lock) { nil }
  let(:yarn_lock) { nil }

  describe "#dependency_file" do
    subject(:dependency_file) { builder.dependency_file }

    context "with an npm lockfile" do
      let(:package_lock) do
        project_dependency_files(project_name).find { |f| f.name == "package-lock.json" }
      end

      context "for a path dependency with no sub-deps" do
        let(:project_name) { "npm6/path_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to eq(true)
          expect(dependency_file.content).
            to eq('{"name":"etag","version":"0.0.1"}')
        end
      end

      context "for a path dependency with sub-deps" do
        let(:project_name) { "npm6/path_dependency_subdeps" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.support_file?).to eq(true)
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
      let(:yarn_lock) do
        project_dependency_files(project_name).find { |f| f.name == "yarn.lock" }
      end

      context "for a path dependency with no sub-deps" do
        let(:project_name) { "yarn/path_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to eq(true)
          expect(dependency_file.content).
            to eq('{"name":"etag","version":"1.8.0"}')
        end
      end

      context "that can't be parsed" do
        let(:project_name) { "yarn/unparseable" }

        it "raises DependencyFileNotParseable" do
          expect { dependency_file }.to raise_error(Dependabot::DependencyFileNotParseable)
        end
      end

      context "for a path dependency with sub-deps" do
        let(:project_name) { "yarn/path_dependency_subdeps" }
        let(:dependency_name) { "other_package" }
        let(:path) { "other_package" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("other_package/package.json")
          expect(dependency_file.support_file?).to eq(true)
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

      context "for a symlinked dependency" do
        let(:project_name) { "yarn/symlinked_dependency" }

        it "builds an imitation path dependency" do
          expect(dependency_file).to be_a(Dependabot::DependencyFile)
          expect(dependency_file.name).to eq("deps/etag/package.json")
          expect(dependency_file.support_file?).to eq(true)
          expect(dependency_file.content).
            to eq('{"name":"etag","version":"1.8.0"}')
        end
      end
    end
  end
end
