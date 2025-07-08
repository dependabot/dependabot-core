# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/elm/update_checker/latest_version_finder"

namespace = Dependabot::Elm::UpdateChecker
RSpec.describe namespace::LatestVersionFinder do
  def elm_version(version_string)
    Dependabot::Elm::Version.new(version_string)
  end

  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:credentials) { [] }
  let(:directory) { "/" }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: [],
      cooldown_options: update_cooldown
    )
  end
  let(:update_cooldown) { nil }
  let(:unlock_requirement) { :own }
  let(:dependency_files) { [elm_json] }
  let(:elm_json) do
    Dependabot::DependencyFile.new(
      name: "elm.json",
      content: fixture("elm_jsons", fixture_name)
    )
  end
  let(:fixture_name) { "app.json" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "elm"
    )
  end
  let(:dependency_name) { "elm/parser" }
  let(:dependency_version) { "1.1.0" }
  let(:dependency_requirements) { [] }
  let(:dependency_requirement) { ">1.0.0" }

  describe "#latest_version" do
    subject(:latest_version) do
      resolver.release_version
    end

    before do
      stub_request(:get, "https://package.elm-lang.org/packages/elm/parser/releases.json")
        .to_return(status: 200, body: fixture("elm_jsons", "elm-parser.json"))
    end

    context "when dealing with an app" do
      context "when no unlocks" do
        let(:unlock_requirement) { :none }

        it { is_expected.to eq(elm_version(dependency_version)) }
      end
    end

    context "when on the latest version" do
      let(:dependency_version) { "1.1.0" }

      it { is_expected.to eq(Dependabot::Elm::Version.new("1.1.0")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version }.not_to raise_error
        end
      end
    end
  end

  describe "#latest_version with cooldown" do
    subject(:latest_version) do
      resolver.release_version
    end

    after do
      Dependabot::Experiments.reset!
    end

    let(:update_cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 7
      )
    end

    before do
      stub_request(:get, "https://package.elm-lang.org/packages/elm/parser/releases.json")
        .to_return(status: 200, body: fixture("elm_jsons", "elm-parser.json"))

      allow(Time).to receive(:now).and_return(Time.parse("2018-08-30 05:29:06 +0000"))
    end

    context "when dealing with an app" do
      context "when no unlocks" do
        let(:unlock_requirement) { :none }

        it { is_expected.to eq(elm_version("1.0.0")) }
      end
    end

    context "when on the latest version" do
      let(:dependency_version) { "1.1.0" }

      it { is_expected.to eq(Dependabot::Elm::Version.new("1.0.0")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version }.not_to raise_error
        end
      end
    end
  end
end
