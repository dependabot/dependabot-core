# frozen_string_literal: true
require "spec_helper"
require "dependabot/update_checkers/cocoa/cocoa_pods/requirements_updater"

klass = Dependabot::UpdateCheckers::Cocoa::CocoaPods::RequirementsUpdater
RSpec.describe klass do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      existing_version: existing_version,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [podfile_requirement].compact }
  let(:podfile_requirement) do
    {
      file: "Podfile",
      requirement: podfile_requirement_string,
      groups: []
    }
  end
  let(:podfile_requirement_string) { "~> 1.4.0" }

  let(:existing_version) { "1.4.0" }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject(:updated_requirements) { updater.updated_requirements }

    context "for a Podfile dependency" do
      subject { updated_requirements.find { |r| r[:file] == "Podfile" } }

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(podfile_requirement) }
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously specified" do
          let(:podfile_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:podfile_requirement_string) { "~> 1.5.0.beta" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "and a minor version was previously specified" do
          let(:podfile_requirement_string) { "~> 1.4" }
          its([:requirement]) { is_expected.to eq("~> 1.5") }
        end

        context "and a greater than or equal to matcher was used" do
          let(:podfile_requirement_string) { ">= 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.5.0") }
        end

        context "and a less than matcher was used" do
          let(:podfile_requirement_string) { "< 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "when there is no `existing_version`" do
          # In this case we don't have a Podfile.lock for this repo, so want
          # slightly different updating behaviour.
          let(:existing_version) { nil }

          context "and the new version satisfies the old requirements" do
            let(:podfile_requirement_string) { "~> 1.4" }
            it { is_expected.to eq(podfile_requirement) }
          end

          context "and the new version does not satisfy the old requirements" do
            let(:podfile_requirement_string) { "~> 1.4.0" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0") }
          end
        end
      end
    end
  end
end
