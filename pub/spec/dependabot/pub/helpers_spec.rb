# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/helpers"

RSpec.describe Dependabot::Pub::Helpers do
  describe ".run_infer_sdk_versions" do
    subject(:versions) { described_class.run_infer_sdk_versions("/project") }

    let(:status) { instance_double(Process::Status, success?: success) }
    let(:success) { true }
    let(:stdout) { JSON.dump("flutter" => "3.24.1", "dart" => "3.5.1", "channel" => "stable") }

    before do
      allow(Open3).to receive(:capture3)
        .with({}, File.join(described_class.pub_helpers_path, "infer_sdk_versions"), "", chdir: "/project")
        .and_return([stdout, "", status])
    end

    it "returns typed SDK versions" do
      expect(versions).to have_attributes(flutter: "3.24.1", dart: "3.5.1", channel: "stable")
    end

    context "when inference fails" do
      let(:success) { false }
      let(:stdout) { "not JSON" }

      it "retains the nil result used by the stable fallback" do
        expect(versions).to be_nil
      end
    end

    ["not JSON", "null", "[]", '{"flutter":false}', '{"flutter":"3.24.1","dart":"3.5.1"}'].each do |payload|
      context "with successful malformed output #{payload}" do
        let(:stdout) { payload }

        it "raises a helper error instead of triggering the stable fallback" do
          expect { versions }.to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed, /infer_sdk_versions/
          ) do |error|
            expect(error.cause).to be_nil
          end
        end
      end
    end
  end
end
