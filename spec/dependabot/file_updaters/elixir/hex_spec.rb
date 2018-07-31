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
      credentials: credentials
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: fixture("elixir", "mixfiles", mixfile_fixture_name),
      name: "mix.exs"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("elixir", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:mixfile_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.4.3",
      requirements:
        [{ file: "mix.exs", requirement: "1.4.3", groups: [], source: nil }],
      previous_version: "1.3.0",
      previous_requirements:
        [{ file: "mix.exs", requirement: "1.3.0", groups: [], source: nil }],
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

    context "without a lockfile" do
      let(:files) { [mixfile] }

      its(:length) { is_expected.to eq(1) }

      describe "the updated mixfile" do
        subject(:updated_mixfile_content) do
          updated_files.find { |f| f.name == "mix.exs" }.content
        end

        it "updates the right dependency" do
          expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
          expect(updated_mixfile_content).to include(%({:phoenix, "== 1.2.1"}))
        end
      end
    end

    describe "the updated mixfile" do
      subject(:updated_mixfile_content) do
        updated_files.find { |f| f.name == "mix.exs" }.content
      end

      it "includes the new requirement" do
        expect(described_class::MixfileUpdater).
          to receive(:new).
          with(dependencies: [dependency], mixfile: mixfile).twice.
          and_call_original

        expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
        expect(updated_mixfile_content).to include(%({:phoenix, "== 1.2.1"}))
      end

      context "with an umbrella app" do
        let(:mixfile_fixture_name) { "umbrella" }
        let(:lockfile_fixture_name) { "umbrella" }

        let(:files) { [mixfile, lockfile, sub_mixfile1, sub_mixfile2] }
        let(:sub_mixfile1) do
          Dependabot::DependencyFile.new(
            name: "apps/dependabot_business/mix.exs",
            content: fixture("elixir", "mixfiles", "dependabot_business")
          )
        end
        let(:sub_mixfile2) do
          Dependabot::DependencyFile.new(
            name: "apps/dependabot_web/mix.exs",
            content: fixture("elixir", "mixfiles", "dependabot_web")
          )
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "plug",
            version: "1.4.5",
            requirements: [
              {
                requirement: "~> 1.4.0",
                file: "apps/dependabot_business/mix.exs",
                groups: [],
                source: nil
              },
              {
                requirement: "1.4.5",
                file: "apps/dependabot_web/mix.exs",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.3.6",
            previous_requirements: [
              {
                requirement: "~> 1.3.0",
                file: "apps/dependabot_business/mix.exs",
                groups: [],
                source: nil
              },
              {
                requirement: "1.3.6",
                file: "apps/dependabot_web/mix.exs",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        end

        it "updates the right files" do
          expect(updated_files.map(&:name)).
            to match_array(
              %w(mix.lock
                 apps/dependabot_business/mix.exs
                 apps/dependabot_web/mix.exs)
            )

          updated_web_content = updated_files.find do |f|
            f.name == "apps/dependabot_web/mix.exs"
          end.content
          expect(updated_web_content).to include(%({:plug, "1.4.5"},))

          updated_business_content = updated_files.find do |f|
            f.name == "apps/dependabot_business/mix.exs"
          end.content
          expect(updated_business_content).to include(%({:plug, "~> 1.4.0"},))
        end
      end
    end

    describe "the updated lockfile" do
      subject(:updated_lockfile_content) do
        updated_files.find { |f| f.name == "mix.lock" }.content
      end

      it "updates the dependency version in the lockfile" do
        expect(described_class::LockfileUpdater).
          to receive(:new).
          with(
            credentials: credentials,
            dependencies: [dependency],
            dependency_files: files
          ).
          and_call_original

        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end
    end
  end
end
