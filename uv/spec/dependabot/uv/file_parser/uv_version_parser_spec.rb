# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/uv/file_parser/uv_version_parser"

RSpec.describe Dependabot::Uv::FileParser::UvVersionParser do
  let(:parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#dependency_set" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    context "with a uv.toml containing an exact pin" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end

      it "returns a single uv dependency" do
        expect(dependencies.length).to eq(1)
        dep = dependencies.first
        expect(dep.name).to eq("uv")
        expect(dep.version).to eq("0.6.12")
        expect(dep.requirements).to eq(
          [{
            requirement: "==0.6.12",
            file: "uv.toml",
            source: nil,
            groups: ["uv-required-version"]
          }]
        )
      end
    end

    context "with a uv.toml containing a range constraint" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_range.toml")
        )
      end

      it "returns a dependency with nil version" do
        expect(dependencies.length).to eq(1)
        dep = dependencies.first
        expect(dep.name).to eq("uv")
        expect(dep.version).to be_nil
        expect(dep.requirements.first[:requirement]).to eq(">=0.6.0")
      end
    end

    context "with no required-version" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "no_required_version.toml")
        )
      end

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "with pyproject.toml containing [tool.uv] required-version" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "uv_required_version.toml")
        )
      end

      it "returns a uv dependency from pyproject.toml" do
        expect(dependencies.length).to eq(1)
        dep = dependencies.first
        expect(dep.name).to eq("uv")
        expect(dep.version).to eq("0.6.12")
        expect(dep.requirements.first[:file]).to eq("pyproject.toml")
      end
    end

    context "with both uv.toml and pyproject.toml containing required-version" do
      let(:dependency_files) { [uv_toml, pyproject] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_exact.toml")
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "uv_required_version.toml")
        )
      end

      it "returns dependencies from both files" do
        uv_deps = dependencies.select { |d| d.name == "uv" }
        files = uv_deps.flat_map { |d| d.requirements.map { |r| r[:file] } }
        expect(files).to include("uv.toml")
        expect(files).to include("pyproject.toml")
      end
    end

    context "with an empty required-version string" do
      let(:dependency_files) { [uv_toml] }
      let(:uv_toml) do
        Dependabot::DependencyFile.new(
          name: "uv.toml",
          content: fixture("uv_toml_files", "required_version_empty.toml")
        )
      end

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end
  end
end
