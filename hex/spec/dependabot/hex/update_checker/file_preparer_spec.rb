# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/hex/update_checker/file_preparer"

RSpec.describe Dependabot::Hex::UpdateChecker::FilePreparer do
  let(:preparer) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      unlock_requirement: unlock_requirement,
      replacement_git_pin: replacement_git_pin,
      latest_allowable_version: latest_allowable_version
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

  let(:latest_allowable_version) { nil }
  let(:version) { "1.3.0" }
  let(:requirements) do
    [{ file: "mix.exs", requirement: "1.3.0", groups: [], source: nil }]
  end
  let(:dependency_name) { "plug" }
  let(:unlock_requirement) { true }
  let(:replacement_git_pin) { nil }

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: fixture("mixfiles", mixfile_fixture_name),
      name: "mix.exs"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: fixture("lockfiles", lockfile_fixture_name),
      name: "mix.lock"
    )
  end
  let(:mixfile_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  describe "#prepared_dependency_files" do
    subject(:prepared_dependency_files) { preparer.prepared_dependency_files }

    context "without a lockfile" do
      let(:dependency_files) { [mixfile] }

      its(:length) { is_expected.to eq(1) }

      describe "the updated mix.exs" do
        subject(:prepared_mixfile) do
          prepared_dependency_files.find { |f| f.name == "mix.exs" }
        end

        it "updates the requirement" do
          expect(prepared_mixfile.content).to include('{:plug, ">= 1.3.0"}')
        end
      end

      context "with a minor version specified" do
        let(:mixfile_fixture_name) { "major_version" }
        let(:requirements) do
          [{ file: "mix.exs", requirement: "~> 1.3", groups: [], source: nil }]
        end

        describe "the updated mix.exs" do
          subject(:prepared_mixfile) do
            prepared_dependency_files.find { |f| f.name == "mix.exs" }
          end

          it "updates the requirement" do
            expect(prepared_mixfile.content).to include('{:plug, ">= 1.3.0"}')
          end
        end
      end
    end

    describe "the updated mix.exs" do
      subject(:prepared_mixfile) do
        prepared_dependency_files.find { |f| f.name == "mix.exs" }
      end

      context "when file loading needs to be sanitized" do
        let(:mixfile_fixture_name) { "loads_file" }

        it "removes the call to load the file" do
          expect(prepared_mixfile.content)
            .to include('@version String.trim("0.0.1")')
        end

        context "when the loading is done without a !" do
          let(:mixfile_fixture_name) { "loads_file_without_bang" }

          it "removes the call to load the file" do
            expect(prepared_mixfile.content)
              .to include('@version String.trim({:ok, "0.0.1"})')
          end
        end

        context "when file loading is done with pipes" do
          let(:mixfile_fixture_name) { "loads_file_with_pipes" }

          it "removes the call to load the file" do
            expect(prepared_mixfile.content)
              .to include('@version {:ok, "0.0.1"} |> String.trim()')
          end
        end

        context "when file loading is done with pipes and a !" do
          let(:mixfile_fixture_name) { "loads_file_with_pipes_and_bang" }

          it "removes the call to load the file" do
            expect(prepared_mixfile.content)
              .to include('@version "0.0.1" |> String.trim()')
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

        context "when there is a latest allowable version" do
          let(:latest_allowable_version) { Gem::Version.new("1.6.0") }

          it "updates the requirement" do
            expect(prepared_mixfile.content)
              .to include('{:plug, ">= 1.3.0 and <= 1.6.0"}')
          end
        end

        context "when there is no version" do
          let(:version) { nil }

          it "updates the requirement" do
            expect(prepared_mixfile.content).to include('{:plug, ">= 1.3.0"}')
          end

          context "when it is a pre-release requirement" do
            let(:mixfile_fixture_name) { "prerelease_version" }
            let(:dependency_name) { "phoenix" }
            let(:requirements) do
              [{
                file: "mix.exs",
                requirement: "1.2.0-rc.0",
                groups: [],
                source: nil
              }]
            end

            it "updates the requirement" do
              expect(prepared_mixfile.content)
                .to include('{:phoenix, ">= 1.2.0-rc.0"}')
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
          [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/phoenix.git",
              branch: "master",
              ref: "v1.2.0"
            }
          }]
        end

        it "updates the pin" do
          expect(prepared_mixfile.content).to include(
            '{:phoenix, ">= 0", github: "dependabot-fixtures/phoenix", ' \
            'ref: "v1.2.1"}'
          )
        end
      end
    end

    describe "the updated mix.lock" do
      subject { prepared_dependency_files.find { |f| f.name == "mix.lock" } }

      it { is_expected.to eq(lockfile) }
    end
  end
end
