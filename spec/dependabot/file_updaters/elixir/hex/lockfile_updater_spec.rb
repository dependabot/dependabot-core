# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/elixir/hex/lockfile_updater"

RSpec.describe Dependabot::FileUpdaters::Elixir::Hex::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
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

  describe "#updated_lockfile_content" do
    subject(:updated_lockfile_content) { updater.updated_lockfile_content }

    it "doesn't store the files permanently" do
      expect { updated_lockfile_content }.
        to_not(change { Dir.entries(tmp_path) })
    end

    it { expect { updated_lockfile_content }.to_not output.to_stdout }

    it "updates the dependency version in the lockfile" do
      expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
      expect(updated_lockfile_content).to include(
        "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
      )
    end

    context "with no requirement" do
      let(:mixfile_fixture_name) { "no_requirement" }
      let(:lockfile_fixture_name) { "no_requirement" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: target_version,
          requirements: [
            { file: "mix.exs", requirement: nil, groups: [], source: nil }
          ],
          previous_version: "1.3.0",
          previous_requirements: [
            { file: "mix.exs", requirement: nil, groups: [], source: nil }
          ],
          package_manager: "hex"
        )
      end

      context "targeting 1.3.2" do
        let(:target_version) { "1.3.2" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :plug, "1.3.2")
          expect(updated_lockfile_content).to include(
            "8391d8ba2e2c187de069211110a882599e851f64550c556163b5130e1e2dbc1b"
          )
        end
      end

      context "targeting 1.3.6" do
        let(:target_version) { "1.3.6" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :plug, "1.3.6")
          expect(updated_lockfile_content).to include(
            "bcdf94ac0f4bc3b804bdbdbde37ebf598bd7ed2bfa5106ed1ab5984a09b7e75f"
          )
        end
      end
    end

    context "when the subdependencies should have changed" do
      let(:mixfile_fixture_name) { "minor_version" }
      let(:lockfile_fixture_name) { "minor_version" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.3.0",
          requirements: [{
            file: "mix.exs",
            requirement: "~> 1.3.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.2.5",
          previous_requirements: [{
            file: "mix.exs",
            requirement: "~> 1.2.1",
            groups: [],
            source: nil
          }],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
        expect(updated_lockfile_content).to include %({:hex, :poison, "3)
      end

      context "with an old-format lockfile" do
        let(:mixfile_fixture_name) { "old_elixir" }
        let(:lockfile_fixture_name) { "old_elixir" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to start_with('%{"mime"')
          expect(updated_lockfile_content).to end_with("}}\n")
          expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
        end
      end
    end

    context "with a mix.exs that opens another file" do
      let(:mixfile_fixture_name) { "loads_file" }
      let(:lockfile_fixture_name) { "exact_version" }

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end
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

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.5")
        expect(updated_lockfile_content).to include(
          "7b13869283fff6b8b21b84b8735326cc012c5eef8607095dc6ee24bd0a273d8e"
        )
      end
    end

    context "with a git dependency" do
      let(:mixfile_fixture_name) { "git_source_no_tag" }
      let(:lockfile_fixture_name) { "git_source_no_tag" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "463e9d282e999fff1737cc6ca09074cf3dbca4ff",
          previous_version: "178ce1a2344515e9145599970313fcc190d4b881",
          requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: nil
            }
          }],
          previous_requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: nil
            }
          }],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include("phoenix.git")
        expect(updated_lockfile_content).
          to_not include("178ce1a2344515e9145599970313fcc190d4b881")
      end
    end
  end
end
