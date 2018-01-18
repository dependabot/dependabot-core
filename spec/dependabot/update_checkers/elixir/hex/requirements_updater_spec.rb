# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/elixir/hex/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [mixfile_req] }
  let(:mixfile_req) do
    {
      file: "composer.json",
      requirement: mixfile_req_string,
      groups: [],
      source: nil
    }
  end
  let(:mixfile_req_string) { "~> 1.4.0" }

  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:mixfile_req_string) { "~> 1.0.0" }
    let(:latest_resolvable_version) { nil }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(mixfile_req_string) }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { "1.5.0" }

      context "and a full version was previously specified" do
        let(:mixfile_req_string) { "1.2.3" }
        its([:requirement]) { is_expected.to eq("1.5.0") }

        context "with an == operator" do
          let(:mixfile_req_string) { "== 1.2.3" }
          its([:requirement]) { is_expected.to eq("== 1.5.0") }
        end
      end

      context "and a partial version was previously specified" do
        let(:mixfile_req_string) { "0.1" }
        its([:requirement]) { is_expected.to eq("1.5") }
      end

      context "and the new version has fewer digits than the old one" do
        let(:mixfile_req_string) { "1.1.0.1" }
        its([:requirement]) { is_expected.to eq("1.5.0") }
      end

      context "and a tilda was previously specified" do
        let(:mixfile_req_string) { "~> 0.2.3" }
        its([:requirement]) { is_expected.to eq("~> 1.5.0") }

        context "specified at two digits" do
          let(:mixfile_req_string) { "~> 0.2" }
          its([:requirement]) { is_expected.to eq("~> 1.5") }
        end

        context "that is already satisfied" do
          let(:mixfile_req_string) { "~> 1.2" }
          its([:requirement]) { is_expected.to eq(mixfile_req_string) }
        end
      end

      context "and a < was previously specified" do
        let(:mixfile_req_string) { "< 1.2.3" }
        its([:requirement]) { is_expected.to eq("< 1.5.1") }

        context "that is already satisfied" do
          let(:mixfile_req_string) { "< 2.0.0" }
          its([:requirement]) { is_expected.to eq(mixfile_req_string) }
        end
      end

      context "and there were multiple specifications" do
        let(:mixfile_req_string) { "> 1.0.0 and < 1.2.0" }
        its([:requirement]) { is_expected.to eq("> 1.0.0 and < 1.6.0") }

        context "that are already satisfied" do
          let(:mixfile_req_string) { "> 1.0.0 and < 2.0.0" }
          its([:requirement]) { is_expected.to eq(mixfile_req_string) }
        end

        context "specified with an or" do
          let(:latest_resolvable_version) { "2.5.0" }

          let(:mixfile_req_string) { "~> 0.2 or ~> 1.0" }

          its([:requirement]) do
            is_expected.to eq("~> 0.2 or ~> 1.0 or ~> 2.5")
          end

          context "one of which is already satisfied" do
            let(:mixfile_req_string) { "~> 0.2 or < 3.0.0" }
            its([:requirement]) { is_expected.to eq(mixfile_req_string) }
          end
        end
      end
    end
  end
end
