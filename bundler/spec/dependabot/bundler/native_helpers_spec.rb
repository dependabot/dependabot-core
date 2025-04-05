# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/native_helpers"

RSpec.describe Dependabot::Bundler::NativeHelpers do
  subject(:native_helper) { described_class }

  describe ".run_bundler_subprocess" do
    let(:options) { {} }

    let(:native_helpers_path) { "/opt" }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)

      with_env("DEPENDABOT_NATIVE_HELPERS_PATH", native_helpers_path) do
        native_helper.run_bundler_subprocess(
          function: "noop",
          args: {},
          bundler_version: "2",
          options: options
        )
      end
    end

    context "with a timeout provided" do
      let(:options) { { timeout_per_operation_seconds: 120 } }

      it "terminates the spawned process when the timeout is exceeded" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 120 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
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
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 1800 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
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
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "timeout -s HUP 60 ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "without a timeout" do
      let(:options) { {} }

      it "does not apply a timeout" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    context "with DEPENDABOT_NATIVE_HELPERS_PATH not set" do
      let(:native_helpers_path) { nil }

      it "uses the full path to the uninstalled run.rb command" do
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_helper_subprocess)
          .with(
            command: "ruby #{File.expand_path('../../../helpers/v2/run.rb', __dir__)}",
            function: "noop",
            args: {},
            env: anything
          )
      end
    end

    private

    def with_env(key, value)
      previous_value = ENV.fetch(key, nil)
      ENV[key] = value
      yield
    ensure
      ENV[key] = previous_value
    end
  end
end
