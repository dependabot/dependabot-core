# typed: false
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

  describe "#dependency_file" do
    subject(:dependency_file) { builder.dependency_file }

    context "with a lockfile" do
      let(:composer_lock) do
        Dependabot::DependencyFile.new(
          name: "composer.lock",
          content: fixture("projects", "path_source", "composer.lock")
        )
      end

      it "builds an imitation path dependency" do
        expect(dependency_file).to be_a(Dependabot::DependencyFile)
        expect(dependency_file.name).to eq("components/path_dep/composer.json")
        expect(dependency_file.support_file?).to be(true)
        expect(JSON.parse(dependency_file.content)["name"])
          .to eq("path_dep/path_dep")
      end

      context "when the path can't be found" do
        let(:path) { "unknown/path_dep" }

        it { is_expected.to be_nil }
      end
    end

    context "without a lockfile" do
      let(:composer_lock) { nil }

      it { is_expected.to be_nil }
    end

    context "with an original package record" do
      let(:record) do
        {
          "name" => "vendor/package",
          "version" => 123,
          "dist" => { "type" => "zip", "url" => path },
          "autoload" => { "psr-4" => { "Vendor\\" => "src/" } },
          "unknown" => { "nested" => [false, nil, { "number" => 4 }] }
        }
      end
      let(:lock_data) { { "packages" => [record, false], "packages-dev" => [record.merge("version" => 456)] } }
      let(:composer_lock) { Dependabot::DependencyFile.new(name: "composer.lock", content: lock_data.to_json) }

      it "serializes the complete first matching entry without requiring a path distribution" do
        expect(dependency_file.content).to eq(record.to_json)
        expect(dependency_file.name).to eq("components/path_dep/composer.json")
        expect(dependency_file.directory).to eq("/")
        expect(dependency_file.support_file?).to be(true)
      end

      context "with false and empty package sections" do
        let(:lock_data) { { "packages" => false, "packages-dev" => {} } }

        it { is_expected.to be_nil }
      end

      context "with invalid JSON" do
        let(:composer_lock) { Dependabot::DependencyFile.new(name: "composer.lock", content: "{ invalid") }

        it { is_expected.to be_nil }
      end
    end
  end
end
