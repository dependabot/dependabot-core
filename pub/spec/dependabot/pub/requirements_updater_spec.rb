# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/version"
require "dependabot/pub/requirements_updater"

RSpec.describe Dependabot::Pub::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      update_strategy: update_strategy,
      tag_for_latest_version: tag_for_latest_version,
      commit_hash_for_latest_version: commit_hash_for_latest_version
    )
  end

  let(:requirements) do
    [{
      requirement: requirement,
      groups: ["dependencies"],
      file: "pubspec.yaml",
      source: source
    }]
  end
  let(:latest_version) { version_class.new("0.3.7") }
  let(:update_strategy) { :bump_versions }
  let(:tag_for_latest_version) { nil }
  let(:commit_hash_for_latest_version) { nil }

  let(:version_class) { Dependabot::Pub::Version }
  let(:requirement) { "^0.2.1" }
  let(:source) do
    {
      type: "hosted",
      url: "https://pub.dartlang.org"
    }
  end

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "with hosted source" do
      context "when there is no latest version" do
        let(:latest_version) { nil }
        it { is_expected.to eq(requirements.first) }
      end

      context "when there is a latest version" do
        let(:latest_version) { version_class.new("0.3.7") }

        context "and no requirement was previously specified" do
          let(:requirement) { nil }
          it { is_expected.to eq(requirements.first) }
        end

        context "and an exact requirement was previously specified" do
          let(:requirement) { "0.3.1" }
          its([:requirement]) { is_expected.to eq("0.3.7") }

          context "and a pre-release version" do
            let(:latest_version) { version_class.new("0.3.7-pre") }
            its([:requirement]) { is_expected.to eq("0.3.7-pre") }
          end
        end

        context "and a ^ requirement was previously specified" do
          context "that is satisfied" do
            let(:requirement) { "^0.3.1" }
            it { is_expected.to eq(requirements.first) }
          end

          context "that is not satisfied" do
            let(:requirement) { "^0.2.1" }
            its([:requirement]) { is_expected.to eq("^0.3.7") }

            context "with strategy widen ranges" do
              let(:update_strategy) { :widen_ranges }
              its([:requirement]) { is_expected.to eq(">=0.2.1 <0.4.0") }
            end
          end
        end
      end
    end

    context "with git source" do
      let(:source) do
        {
          type: "git",
          url: git_url,
          path: git_path,
          branch: nil,
          ref: git_ref,
          resolved_ref: "version_hash_#{git_ref}"
        }
      end
      let(:requirement) { git_url }
      let(:git_url) { "https://github.com/dart-lang/path.git" }
      let(:git_path) { "." }
      let(:git_ref) { "0.2.1" }

      let(:tag_for_latest_version) { latest_version&.to_s }
      let(:commit_hash_for_latest_version) do
        return "version_hash_#{tag_for_latest_version}" if tag_for_latest_version

        nil
      end

      context "when there is no latest version" do
        let(:latest_version) { nil }
        it { is_expected.to eq(requirements.first) }
      end

      context "when there is a latest version" do
        let(:latest_version) { version_class.new("0.3.7") }

        its([:source]) do
          is_expected.to eq(
            {
              type: "git",
              url: "https://github.com/dart-lang/path.git",
              path: ".",
              branch: nil,
              ref: "0.3.7",
              resolved_ref: "version_hash_0.3.7"
            }
          )
        end
      end
    end
  end
end
