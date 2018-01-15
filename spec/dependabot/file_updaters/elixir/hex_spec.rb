# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/elixir/hex"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Elixir::Hex do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(content: mixfile_body, name: "mix.exs")
  end
  let(:mixfile_body) { fixture("elixir", "mixfiles", "exact_version") }
  let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "mix.lock", content: lockfile_body)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.4.3",
      requirements: [
        { file: "mix.exs", requirement: "1.4.3", groups: [], source: nil }
      ],
      previous_version: "1.3.0",
      previous_requirements: [
        { file: "mix.exs", requirement: "1.3.0", groups: [], source: nil }
      ],
      package_manager: "hex"
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    it { expect { updated_files }.to_not output.to_stdout }
    its(:length) { is_expected.to eq(2) }

    describe "the updated mixfile" do
      subject(:updated_mixfile_content) do
        updated_files.find { |f| f.name == "mix.exs" }.content
      end

      it { is_expected.to include %({:plug, "1.4.3"},) }
      it { is_expected.to include %({:phoenix, "== 1.2.1"}) }
    end

    describe "the updated lockfile" do
      # TODO
    end
  end
end
