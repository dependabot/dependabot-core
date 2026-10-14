# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"

RSpec.describe Dependabot::NpmAndYarn::SubDependencyFilesFilterer do
  subject(:files_requiring_update) do
    described_class.new(
      dependency_files: dependency_files,
      updated_dependencies: updated_dependencies
    ).files_requiring_update
  end

  let(:dependency_files) do
    project_dependency_files(project_name)
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "extend",
      version: "2.0.2",
      previous_version: nil,
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  let(:project_name) { "npm6_and_yarn/nested_sub_dependency_update" }
  let(:updated_dependencies) { [dependency] }

  def project_dependency_file(file_name)
    dependency_files.find { |f| f.name == file_name }
  end

  describe ".files_requiring_update" do
    it do
      expect(files_requiring_update).to contain_exactly(
        project_dependency_file("packages/package1/package-lock.json"),
        project_dependency_file("packages/package3/yarn.lock")
      )
    end

    context "when installation names refer to different npm packages" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ms",
          version: "6.0.0",
          requirements: [],
          package_manager: "npm_and_yarn",
          metadata: { npm_package_name: "is-number" }
        )
      end
      let(:dependency_files) do
        {
          "older/package-lock.json" => [["is-number", "1.0.0"]],
          "higher/package-lock.json" => [["ms", "2.0.0"], ["is-number", "7.0.0"]],
          "equal/package-lock.json" => [["ms", "2.0.0"], ["is-number", "6.0.0"]],
          "ordinary/package-lock.json" => [["ms", "2.0.0"]],
          "mixed/package-lock.json" => [["ms", "2.0.0"], ["is-number", "4.0.0"]],
          "other-alias/package-lock.json" => [["is-odd", "2.0.0"]]
        }.map do |name, records|
          packages = records.each_with_index.to_h do |(target, version), index|
            path = index.zero? ? "node_modules/ms" : "node_modules/parent/node_modules/ms"
            [path, { "name" => target, "version" => version }]
          end
          Dependabot::DependencyFile.new(
            name: name,
            content: { "lockfileVersion" => 3, "packages" => packages }.to_json
          )
        end
      end

      it "selects only lockfiles with an older version of the requested alias target" do
        expect(files_requiring_update.map(&:name))
          .to contain_exactly("older/package-lock.json", "mixed/package-lock.json")
      end

      context "when updating the ordinary package" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "ms",
            version: "2.1.3",
            requirements: [],
            package_manager: "npm_and_yarn"
          )
        end

        it "does not mistake aliases for ordinary installations" do
          expect(files_requiring_update.map(&:name)).to contain_exactly(
            "higher/package-lock.json",
            "equal/package-lock.json",
            "ordinary/package-lock.json",
            "mixed/package-lock.json"
          )
        end
      end
    end

    context "when the version is out of range" do
      let(:project_name) { "npm6_and_yarn/nested_sub_dependency_update_npm_out_of_range" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "extend",
          version: "1.3.0",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it do
        expect(files_requiring_update).to contain_exactly(
          project_dependency_file("packages/package4/package-lock.json")
        )
      end
    end
  end
end
