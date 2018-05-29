# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/elixir/hex/file_preparer"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      unlock_requirement: unlock_requirement,
      replacement_git_pin: replacement_git_pin
    )
  end

  let(:dependency_files) { [mixfile, lockfile] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: requirements,
      package_manager: "hex"
    )
  end

  let(:version) { "1.3.0" }
  let(:requirements) do
    [{ file: "mix.exs", requirement: "1.3.0", groups: [], source: nil }]
  end
  let(:dependency_name) { "plug" }
  let(:unlock_requirement) { true }
  let(:replacement_git_pin) { nil }

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: fixture("elixir", "mixfiles", mixfile_fixture_name),
      name: "mix.exs"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: fixture("elixir", "lockfiles", lockfile_fixture_name),
      name: "mix.lock"
    )
  end
  let(:mixfile_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    describe "the updated mix.exs" do
      subject(:prepared_mixfile) do
        prepared_dependency_files.find { |f| f.name == "mix.exs" }
      end

      context "when file loading needs to be sanitized" do
        let(:mixfile_fixture_name) { "loads_file" }

        it "removes the call to load the file" do
          expect(prepared_mixfile.content).
            to include('@version String.trim("0.0.1")')
        end

        context "an the loading is done without a !" do
          let(:mixfile_fixture_name) { "loads_file_without_bang" }

          it "removes the call to load the file" do
            expect(prepared_mixfile.content).
              to include('@version String.trim({:ok, "0.0.1"})')
          end
        end
      end

      context "with unlock_requirement set to false" do
        let(:unlock_requirement) { false }

        it "doesn't update the requirement" do
          expect(prepared_mixfile.content).to include('{:plug, "1.3.0"}')
        end
      end

      context "with unlock_requirement set to true" do
        let(:unlock_requirement) { true }

        it "updates the requirement" do
          expect(prepared_mixfile.content).to include('{:plug, ">= 1.3.0"}')
        end

        context "and no version" do
          let(:version) { nil }

          it "updates the requirement" do
            expect(prepared_mixfile.content).to include('{:plug, ">= 1.3.0"}')
          end

          context "but a pre-release requirement" do
            let(:mixfile_fixture_name) { "prerelease_version" }
            let(:dependency_name) { "phoenix" }
            let(:requirements) do
              [
                {
                  file: "mix.exs",
                  requirement: "1.2.0-rc.0",
                  groups: [],
                  source: nil
                }
              ]
            end

            it "updates the requirement" do
              expect(prepared_mixfile.content).
                to include('{:phoenix, ">= 1.2.0-rc.0"}')
            end
          end
        end
      end

      context "with a git pin to replace" do
        let(:replacement_git_pin) { "v1.2.1" }
        let(:mixfile_fixture_name) { "git_source" }
        let(:version) { "178ce1a2344515e9145599970313fcc190d4b881" }
        let(:dependency_name) { "phoenix" }
        let(:requirements) do
          [
            {
              requirement: nil,
              file: "mix.exs",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/phoenixframework/phoenix.git",
                branch: "master",
                ref: "v1.2.0"
              }
            }
          ]
        end

        it "updates the pin" do
          expect(prepared_mixfile.content).to include(
            '{:phoenix, ">= 0", github: "phoenixframework/phoenix", '\
            'ref: "v1.2.1"}'
          )
        end

        context "that uses single quoates" do
          let(:mixfile_fixture_name) { "git_source_with_charlist" }

          it "updates the pin" do
            expect(prepared_mixfile.content).to include(
              '{:phoenix, ">= 0", github: "phoenixframework/phoenix", '\
              "ref: \'v1.2.1\'}"
            )
          end
        end
      end
    end

    describe "the updated mix.lock" do
      subject { prepared_dependency_files.find { |f| f.name == "mix.lock" } }
      it { is_expected.to eq(lockfile) }
    end
  end
end
