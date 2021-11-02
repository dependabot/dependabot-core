# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/native_helpers"

RSpec.describe Dependabot::Bundler::NativeHelpers do
  subject { described_class }

  describe ".run_bundler_subprocess" do
    context "with a timeout provided" do
      it "terminates the spawned process when the timeout is exceeded" do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)

        subject.run_bundler_subprocess(
          function: "noop",
          args: [],
          bundler_version: "2.0.0",
          options: {
            timeout_per_operation_seconds: 1
          }
        )

        expect(Dependabot::SharedHelpers).
          to have_received(:run_helper_subprocess).
          with(
            command: "timeout -s HUP 1 bundle exec ruby /opt/bundler/v2/run.rb",
            function: "noop",
            args: [],
            env: anything
          )
      end
    end
  end
end
