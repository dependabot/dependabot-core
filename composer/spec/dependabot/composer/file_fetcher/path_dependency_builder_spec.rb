# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/file_fetcher/path_dependency_builder"

RSpec.describe Dependabot::Composer::FileFetcher::PathDependencyBuilder do
  let(:builder) do
    described_class.new(
      path: path,
      directory: directory,
      lockfile: composer_lock
    )
  end

  let(:path) { "components/path_dep" }
  let(:directory) { "/" }
  let(:composer_lock) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end

  let(:lockfile_fixture_name) { "path_source" }

  describe "#dependency_file" do
    subject(:dependency_file) { builder.dependency_file }

    context "with a lockfile" do
      let(:composer_lock) do
        Dependabot::DependencyFile.new(
          name: "composer.lock",
          content: fixture("lockfiles", lockfile_fixture_name)
        )
      end
      let(:lockfile_fixture_name) { "path_source" }

      it "builds an imitation path dependency" do
        expect(dependency_file).to be_a(Dependabot::DependencyFile)
        expect(dependency_file.name).to eq("components/path_dep/composer.json")
        expect(dependency_file.support_file?).to eq(true)
        expect(JSON.parse(dependency_file.content)["name"]).
          to eq("path_dep/path_dep")
      end

      context "for a path that can't be found" do
        let(:path) { "unknown/path_dep" }
        it { is_expected.to be_nil }
      end
    end

    context "without a lockfile" do
      let(:composer_lock) { nil }
      it { is_expected.to be_nil }
    end
  end
end
