# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/elixir/hex/mixfile_updater"

RSpec.describe Dependabot::FileUpdaters::Elixir::Hex::MixfileUpdater do
  let(:updater) do
    described_class.new(
      mixfile: mixfile,
      dependencies: [dependency]
    )
  end

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: fixture("elixir", "mixfiles", mixfile_fixture_name),
      name: "mix.exs"
    )
  end
  let(:mixfile_fixture_name) { "exact_version" }

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

  describe "#updated_mixfile_content" do
    subject(:updated_mixfile_content) { updater.updated_mixfile_content }

    it "updates the right dependency" do
      expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
      expect(updated_mixfile_content).to include(%({:phoenix, "== 1.2.1"}))
    end

    context "with a git dependency having its reference updated" do
      let(:mixfile_fixture_name) { "git_source_tag_can_update" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "aa218f56b14c9653891f9e74264a383fa43fefbd",
          requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: "v1.3.0"
            }
          }],
          previous_version: "178ce1a2344515e9145599970313fcc190d4b881",
          previous_requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: "v1.2.0"
            }
          }],
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
      let(:mixfile_fixture_name) { "similar_names" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: "1.4.3",
          requirements: [{
            file: "mix.exs",
            requirement: "~> 1.4",
            groups: [],
            source: nil
          }],
          previous_version: "1.3.5",
          previous_requirements: [{
            file: "mix.exs",
            requirement: "~> 1.3",
            groups: [],
            source: nil
          }],
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
      let(:mixfile_fixture_name) { "loads_file" }

      it "doesn't leave the temporary edits present" do
        expect(updated_mixfile_content).to include(%({:plug, "1.4.3"},))
        expect(updated_mixfile_content).to include(%(File.read!("VERSION")))
      end
    end
  end
end
