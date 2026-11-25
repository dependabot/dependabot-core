# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_updater/pipfile_file_updater"

RSpec.describe Dependabot::Python::FileUpdater::PipfileFileUpdater do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  subject(:updated_files) { updater.updated_dependency_files }

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Python::FileUpdater::PipfileFileUpdater) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:updater) do
    described_class.new(
      dependencies: [dependency],
      dependency_files: [pipfile, lockfile],
      credentials: [],
      repo_contents_path: nil
    )
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    requirement = { requirement: "*", file: "Pipfile", source: nil, groups: ["default"] }
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.18.4",
      previous_version: "2.18.0",
      package_manager: "pip",
      requirements: [requirement],
      previous_requirements: [requirement]
    )
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfile_files", "version_not_specified")
    )
  end

  sig { returns(Dependabot::DependencyFile) }
  let(:lockfile) { Dependabot::DependencyFile.new(name: "Pipfile.lock", content: lockfile_content) }

  sig { returns(String) }
  let(:lockfile_content) { fixture("pipfile_files", "version_not_specified.lock") }

  sig { returns(Dependabot::Python::PipenvRunner) }
  let(:runner) { instance_double(Dependabot::Python::PipenvRunner) }

  sig { returns(Dependabot::Python::LanguageVersionManager) }
  let(:language_version_manager) do
    instance_double(
      Dependabot::Python::LanguageVersionManager,
      python_major_minor: "3.10.22",
      install_required_python: nil
    )
  end

  sig { returns(Object) }
  let(:helper_result) { { "not" => "a checksum" } }
  # rubocop:enable RSpec/ScatteredLet

  before do
    allow(Dependabot::Python::LanguageVersionManager).to receive(:new).and_return(language_version_manager)
    allow(Dependabot::Python::PipenvRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:run_upgrade).with("==2.18.4") do
      File.write("Pipfile.lock", T.must(lockfile.content))
      ""
    end
    allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
      .with(hash_including(function: "get_pipfile_hash")).and_return(helper_result)
  end

  it "rejects a malformed checksum result with helper context" do
    expect { updated_files }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
      expect(error.message).to include("get_pipfile_hash", "string")
      expect(error.error_context).to include(function: "get_pipfile_hash")
    end
  end

  context "with malformed original metadata" do
    sig { returns(String) }
    let(:lockfile_content) { JSON.parse(super()).merge("_meta" => false).to_json }

    it "fails before invoking Pipenv" do
      expect(runner).not_to receive(:run_upgrade)

      expect { updated_files }
        .to raise_error(Dependabot::DependencyFileNotParseable, /Pipfile\.lock _meta/)
    end
  end
end
