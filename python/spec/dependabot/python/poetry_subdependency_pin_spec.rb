# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python"
require "dependabot/python/poetry_subdependency_pin"

RSpec.describe Dependabot::Python::PoetrySubdependencyPin do
  let(:pyproject_dir) { "pyproject_files" }
  let(:lockfile_dir) { "poetry_locks" }
  let(:pyproject) do
    Dependabot::DependencyFile.new(name: "pyproject.toml", content: fixture(pyproject_dir, "#{fixture_name}.toml"))
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "poetry.lock", content: fixture(lockfile_dir, "#{fixture_name}.lock"))
  end

  before { Dependabot::Experiments.register(:enable_native_poetry_helper, true) }
  after { Dependabot::Experiments.reset! }

  def pinned_toml(name, project:)
    document = Dependabot::Python::FileParser::PyprojectDocument.from_file(pyproject)
    described_class.new(lockfile, name, project: project).pin!(document, "#{name}==1.0.0")
    document.to_toml
  rescue described_class::ScopeNotReproducible => e
    e.class
  end

  %w(
    poetry_v2_pep621_only
    poetry_v2_pep621_only_dev_group
    poetry_v2_pep621_only_extra
    poetry_v2_pep621_only_main_env_marker
  ).each do |name|
    context "with #{name}" do
      let(:fixture_name) { name }

      it "pins every locked package the same way with Poetry's view of the lockfile" do
        project = Dependabot::Python::PoetryProject.load(pyproject: pyproject, lockfile: lockfile)

        project.locked_packages.map(&:name).uniq.each do |package|
          expect(pinned_toml(package, project: project)).to eq(pinned_toml(package, project: nil)), package
        end
      end
    end
  end

  context "with a package locked at several versions" do
    let(:fixture_name) { "poetry_native_multiple_locked_versions" }
    let(:pyproject_dir) { "dependency_grapher" }
    let(:lockfile_dir) { "dependency_grapher" }

    it "declines to pin it using only the native project" do
      project = Dependabot::Python::PoetryProject.load(pyproject: pyproject, lockfile: lockfile)

      expect { described_class.new(nil, "urllib3", project: project).ensure_single_version! }
        .to raise_error(described_class::ScopeNotReproducible)
    end
  end
end
