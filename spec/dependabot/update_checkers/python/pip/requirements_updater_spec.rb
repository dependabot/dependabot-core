# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/python/pip/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Python::Pip::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [requirement_txt_req, setup_py_req].compact }
  let(:requirement_txt_req) do
    {
      file: "requirements.txt",
      requirement: requirement_txt_req_string,
      groups: [],
      source: nil
    }
  end
  let(:setup_py_req) do
    {
      file: "setup.py",
      requirement: setup_py_req_string,
      groups: [],
      source: nil
    }
  end
  let(:requirement_txt_req_string) { "==1.4.0" }
  let(:setup_py_req_string) { ">= 1.4.0" }

  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject(:updated_requirements) { updater.updated_requirements }

    context "for a requirements.txt dependency" do
      subject do
        updated_requirements.find { |r| r[:file] == "requirements.txt" }
      end

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(requirement_txt_req) }
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously pinned" do
          let(:requirement_txt_req_string) { "==1.4.0" }
          its([:requirement]) { is_expected.to eq("==1.5.0") }

          context "that has fewer digits than the new version" do
            let(:requirement_txt_req_string) { "==1.4.0" }
            let(:latest_resolvable_version) { "1.5.0.1" }
            its([:requirement]) { is_expected.to eq("==1.5.0.1") }
          end
        end

        context "and no requirement was specified" do
          let(:requirement_txt_req_string) { nil }
          it { is_expected.to eq(requirement_txt_req) }
        end

        context "and a range requirement was specified" do
          let(:requirement_txt_req_string) { ">=1.3.0" }
          it { is_expected.to eq(requirement_txt_req) }

          context "with an upper bound" do
            let(:requirement_txt_req_string) { ">=1.3.0, <=1.5.0" }
            it { is_expected.to eq(requirement_txt_req) }

            context "that needs updating" do
              let(:requirement_txt_req_string) { ">=1.3.0, <1.5" }
              its([:requirement]) { is_expected.to eq(">=1.3.0,<1.6") }
            end
          end
        end

        context "and a compatibility requirement was specified" do
          let(:requirement_txt_req_string) { "~=1.3.0" }
          its([:requirement]) { is_expected.to eq("~=1.5.0") }

          context "that supports the new version" do
            let(:requirement_txt_req_string) { "~=1.3" }
            its([:requirement]) { is_expected.to eq("~=1.5") }
          end

          context "that needs to be upated and maintain its precision" do
            let(:requirement_txt_req_string) { "~=1.3" }
            let(:latest_resolvable_version) { "2.1.0" }
            its([:requirement]) { is_expected.to eq("~=2.1") }
          end
        end

        context "and a prefix match was specified" do
          context "that is satisfied" do
            let(:requirement_txt_req_string) { "==1.*.*" }
            it { is_expected.to eq(requirement_txt_req) }
          end

          context "that needs updating" do
            let(:requirement_txt_req_string) { "==1.4.*" }
            its([:requirement]) { is_expected.to eq("==1.5.*") }
          end

          context "along with an exact match" do
            let(:requirement_txt_req_string) { "==1.4.*, ==1.4.1" }
            its([:requirement]) { is_expected.to eq("==1.5.0") }
          end
        end
      end
    end

    context "for a setup.py dependency" do
      subject { updated_requirements.find { |r| r[:file] == "setup.py" } }

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(setup_py_req) }
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously pinned" do
          let(:setup_py_req_string) { "==1.4.0" }
          its([:requirement]) { is_expected.to eq("==1.5.0") }

          context "that has fewer digits than the new version" do
            let(:setup_py_req_string) { "==1.4.0" }
            let(:latest_resolvable_version) { "1.5.0.1" }
            its([:requirement]) { is_expected.to eq("==1.5.0.1") }
          end
        end

        context "and no requirement was specified" do
          let(:setup_py_req_string) { nil }
          it { is_expected.to eq(setup_py_req) }
        end

        context "and a range requirement was specified" do
          let(:setup_py_req_string) { ">=1.3.0" }
          it { is_expected.to eq(setup_py_req) }

          context "with an upper bound" do
            let(:setup_py_req_string) { ">=1.3.0, <=1.5.0" }
            it { is_expected.to eq(setup_py_req) }

            context "that needs updating" do
              let(:setup_py_req_string) { ">=1.3.0, <1.5" }
              its([:requirement]) { is_expected.to eq(">=1.3.0,<1.6") }
            end
          end
        end

        context "and a compatibility requirement was specified" do
          let(:setup_py_req_string) { "~=1.3.0" }
          its([:requirement]) { is_expected.to eq(">=1.3,<1.6") }

          context "that supports the new version" do
            let(:setup_py_req_string) { "~=1.3" }
            it { is_expected.to eq(setup_py_req) }
          end

          context "that needs to be upated and maintain its precision" do
            let(:setup_py_req_string) { "~=1.3" }
            let(:latest_resolvable_version) { "2.1.0" }
            its([:requirement]) { is_expected.to eq(">=1.3,<3.0") }
          end
        end

        context "and a prefix match was specified" do
          context "that is satisfied" do
            let(:setup_py_req_string) { "==1.*.*" }
            it { is_expected.to eq(setup_py_req) }
          end

          context "that needs updating" do
            let(:setup_py_req_string) { "==1.4.*" }
            its([:requirement]) { is_expected.to eq(">=1.4,<1.6") }
          end

          context "along with an exact match" do
            let(:setup_py_req_string) { "==1.4.*, ==1.4.1" }
            its([:requirement]) { is_expected.to eq("==1.5.0") }
          end
        end
      end
    end
  end
end
