# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/native_helpers"

RSpec.describe Dependabot::Bundler::NativeHelpers do
  subject { described_class }

  describe ".run_bundler_subprocess" do
    let(:options) { {} }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
      allow(ENV).to receive(:[]).with("DEPENDABOT_NATIVE_HELPERS_PATH").and_return("/opt")

      subject.run_bundler_subprocess(
        function: "noop",
        args: [],
        bundler_version: "2.0.0",
        options: options
      )
    end

    context "with a timeout provided" do
      let(:options) { { timeout_per_operation_seconds: 120 } }

      it "terminates the spawned process when the timeout is exceeded" do
        expect(Dependabot::SharedHelpers).
          to have_received(:run_helper_subprocess).
          with(
            command: "timeout -s HUP 120 bundle exec ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: [],
            env: anything
          )
      end
    end

    context "with a timeout that is too high" do
      let(:thirty_minutes_plus_one_second) { 1801 }
      let(:options) do
        {
          timeout_per_operation_seconds: thirty_minutes_plus_one_second
        }
      end

      it "applies the maximum timeout" do
        expect(Dependabot::SharedHelpers).
          to have_received(:run_helper_subprocess).
          with(
            command: "timeout -s HUP 1800 bundle exec ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: [],
            env: anything
          )
      end
    end

    context "with a timeout that is too low" do
      let(:fifty_nine_seconds) { 59 }
      let(:options) do
        {
          timeout_per_operation_seconds: fifty_nine_seconds
        }
      end

      it "applies the minimum timeout" do
        expect(Dependabot::SharedHelpers).
          to have_received(:run_helper_subprocess).
          with(
            command: "timeout -s HUP 60 bundle exec ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: [],
            env: anything
          )
      end
    end

    context "without a timeout" do
      let(:options) { {} }

      it "does not apply a timeout" do
        expect(Dependabot::SharedHelpers).
          to have_received(:run_helper_subprocess).
          with(
            command: "bundle exec ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: [],
            env: anything
          )
      end
    end
  end
end
