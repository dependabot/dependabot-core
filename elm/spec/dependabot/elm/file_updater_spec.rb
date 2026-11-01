# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/elm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Elm::FileUpdater do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(String) }
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "elm/regex",
      version: "1.1.0",
      requirements: [{
        file: "elm.json",
        requirement: "1.1.0",
        groups: [],
        source: nil
      }],
      previous_version: "1.0.0",
      previous_requirements: [{
        file: "elm.json",
        requirement: "1.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "elm"
    )
  end
  sig { returns(String) }
  let(:elm_json_file_fixture_name) { "app.json" }
  sig { returns(Dependabot::DependencyFile) }
  let(:elm_json_file) do
    Dependabot::DependencyFile.new(
      content: fixture("elm_jsons", elm_json_file_fixture_name),
      name: "elm.json"
    )
  end
  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:files) { [elm_json_file] }
  sig { returns(T::Array[Dependabot::Credential]) }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  sig { returns(Dependabot::Elm::FileUpdater) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  before { FileUtils.mkdir_p(tmp_path) }

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.not_to(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.not_to output.to_stdout }
    its(:length) { is_expected.to eq(1) }

    describe "the elm.json file" do
      sig { returns(String) }
      subject(:updated_elm_json_file_content) do
        T.must(T.must(updated_files.find { |f| f.name == "elm.json" }).content)
      end

      it "updates the right dependency" do
        expect(updated_elm_json_file_content)
          .to include(%("elm/regex": "1.1.0"))
        expect(updated_elm_json_file_content)
          .to include(%("elm/html": "1.0.0"))
      end
    end
  end
end
