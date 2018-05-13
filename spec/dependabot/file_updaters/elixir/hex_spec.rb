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

      it "updates the right dependency" do
        expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
        expect(updated_mixfile_content).to include(%({:phoenix, "== 1.2.1"}))
      end

      context "with a git dependency having its reference updated" do
        let(:mixfile_body) do
          fixture("elixir", "mixfiles", "git_source_tag_can_update")
        end
        let(:lockfile_body) do
          fixture("elixir", "lockfiles", "git_source_tag_can_update")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "aa218f56b14c9653891f9e74264a383fa43fefbd",
            requirements: [
              {
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: "v1.3.0"
                }
              }
            ],
            previous_version: "178ce1a2344515e9145599970313fcc190d4b881",
            previous_requirements: [
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
            ],
            package_manager: "hex"
          )
        end

        it "updates the right dependency" do
          expect(updated_mixfile_content).to include(%({:plug, "1.3.3"},))
          expect(updated_mixfile_content).to include(
            %({:phoenix, github: "phoenixframework/phoenix", ref: "v1.3.0"})
          )
        end
      end

      context "with similarly named packages" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "similar_names") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "similar_names") }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "plug",
            version: "1.4.3",
            requirements: [
              {
                file: "mix.exs",
                requirement: "~> 1.4",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.3.5",
            previous_requirements: [
              {
                file: "mix.exs",
                requirement: "~> 1.3",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        end

        it "updates the right dependency" do
          expect(updated_mixfile_content).to include(%({:plug, "~> 1.4"},))
          expect(updated_mixfile_content).
            to include(%({:absinthe_plug, "~> 1.3"},))
          expect(updated_mixfile_content).
            to include(%({:plug_cloudflare, "~> 1.3"}))
        end
      end

      context "with a mix.exs that opens another file" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "loads_file") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

        it "doesn't leave the temporary edits present" do
          expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
          expect(updated_mixfile_content).to include(%(File.read!("VERSION")))
        end
      end

      context "with an umbrella app" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "umbrella") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "umbrella") }
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
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end

      context "when the subdependencies should have changed" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "1.3.0",
            requirements: [
              {
                file: "mix.exs",
                requirement: "~> 1.3.0",
                groups: [],
                source: nil
              }
            ],
            previous_version: "1.2.5",
            previous_requirements: [
              {
                file: "mix.exs",
                requirement: "~> 1.2.1",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        end

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
          expect(updated_lockfile_content).to include %({:hex, :poison, "3)
        end

        context "with an old-format lockfile" do
          let(:mixfile_body) { fixture("elixir", "mixfiles", "old_elixir") }
          let(:lockfile_body) { fixture("elixir", "lockfiles", "old_elixir") }

          it "updates the dependency version in the lockfile" do
            expect(updated_lockfile_content).to start_with('%{"mime"')
            expect(updated_lockfile_content).to end_with("}}\n")
            expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
          end
        end
      end

      context "with a mix.exs that opens another file" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "loads_file") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
          expect(updated_lockfile_content).to include(
            "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
          )
        end
      end

      context "with an umbrella app" do
        let(:mixfile_body) { fixture("elixir", "mixfiles", "umbrella") }
        let(:lockfile_body) { fixture("elixir", "lockfiles", "umbrella") }
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
        let(:mixfile_body) do
          fixture("elixir", "mixfiles", "git_source_no_tag")
        end
        let(:lockfile_body) do
          fixture("elixir", "lockfiles", "git_source_no_tag")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "463e9d282e999fff1737cc6ca09074cf3dbca4ff",
            previous_version: "178ce1a2344515e9145599970313fcc190d4b881",
            requirements: [
              {
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: nil
                }
              }
            ],
            previous_requirements: [
              {
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: nil
                }
              }
            ],
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
end
