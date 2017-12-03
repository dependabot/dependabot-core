# frozen_string_literal: true

require "spec_helper"
require "dependabot/update_checkers/java_script/base/requirements_updater"

module_to_test = Dependabot::UpdateCheckers::JavaScript
RSpec.describe module_to_test::Base::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      existing_version: existing_version,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [package_json_req] }
  let(:package_json_req) do
    {
      file: "package.json",
      requirement: package_json_req_string,
      groups: [],
      source: nil
    }
  end
  let(:package_json_req_string) { "^1.4.0" }

  let(:existing_version) { "1.0.0" }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    let(:package_json_req_string) { "^1.0.0" }
    let(:latest_resolvable_version) { nil }

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(package_json_req_string) }
    end

    context "with an existing version" do
      let(:existing_version) { "1.0.0" }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          let(:package_json_req_string) { "^1.2.3" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:package_json_req_string) { "^1.2.3-rc1" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and a pre-release was previously specified with four places" do
          let(:package_json_req_string) { "^1.2.3.rc1" }
          its([:requirement]) { is_expected.to eq("^1.5.0") }
        end

        context "and an x.x was previously specified" do
          let(:package_json_req_string) { "^0.x.x" }
          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "and an x.x was previously specified with four places" do
          let(:package_json_req_string) { "^0.x.x.rc1" }
          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "and there were multiple requirements" do
          let(:requirements) { [package_json_req, other_package_json_req] }

          let(:other_package_json_req) do
            {
              file: "another/package.json",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:package_json_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.x.x" }

          it "updates both requirements" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "package.json",
                  requirement: "^1.5.0",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/package.json",
                  requirement: "^1.x.x",
                  groups: [],
                  source: nil
                }
              ]
            )
          end
        end
      end
    end

    context "without an existing version" do
      let(:existing_version) { nil }

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:package_json_req_string) { "1.2.3" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and a partial version was previously specified" do
          let(:package_json_req_string) { "0.1" }
          its([:requirement]) { is_expected.to eq("1.5") }
        end

        context "and only the major part was previously specified" do
          let(:package_json_req_string) { "1" }
          let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and the new version has fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          its([:requirement]) { is_expected.to eq("1.5.0") }
        end

        context "and the new version has much fewer digits than the old one" do
          let(:package_json_req_string) { "1.1.0.1" }
          let(:latest_resolvable_version) { Gem::Version.new("4") }
          its([:requirement]) { is_expected.to eq("4") }
        end

        context "and a caret was previously specified" do
          context "that satisfies the latest version" do
            let(:package_json_req_string) { "^1.2.3" }
            its([:requirement]) { is_expected.to eq("^1.2.3") }
          end

          context "that does not satisfy the latest version" do
            let(:package_json_req_string) { "^0.8.0" }
            its([:requirement]) { is_expected.to eq("^1.5.0") }
          end

          context "including a pre-release" do
            let(:package_json_req_string) { "^1.2.3-rc1" }
            its([:requirement]) { is_expected.to eq("^1.2.3-rc1") }
          end

          context "including a pre-release with four places" do
            let(:package_json_req_string) { "^1.2.3.rc1" }
            its([:requirement]) { is_expected.to eq("^1.2.3.rc1") }
          end
        end

        context "and an x.x was previously specified" do
          let(:package_json_req_string) { "0.x.x" }
          its([:requirement]) { is_expected.to eq("1.x.x") }
        end

        context "and an x.x was previously specified with four places" do
          let(:package_json_req_string) { "^0.x.x.rc1" }
          its([:requirement]) { is_expected.to eq("^1.x.x") }
        end

        context "and there were multiple requirements" do
          let(:requirements) { [package_json_req, other_package_json_req] }

          let(:other_package_json_req) do
            {
              file: "another/package.json",
              requirement: other_requirement_string,
              groups: [],
              source: nil
            }
          end
          let(:package_json_req_string) { "^1.2.3" }
          let(:other_requirement_string) { "^0.x.x" }

          it "updates the requirement that needs to be updated" do
            expect(updater.updated_requirements).to match_array(
              [
                {
                  file: "package.json",
                  requirement: "^1.2.3",
                  groups: [],
                  source: nil
                },
                {
                  file: "another/package.json",
                  requirement: "^1.x.x",
                  groups: [],
                  source: nil
                }
              ]
            )
          end
        end
      end
    end
  end
end
