# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Deno::Helpers do
  describe ".run_deno_command" do
    let(:dir) { "/tmp/some-dir" }

    it "delegates to SharedHelpers.run_shell_command with scoped DENO_DIR" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          "deno install --frozen=false",
          cwd: dir,
          env: hash_including("DENO_DIR" => "#{dir}/.deno_cache")
        )
        .and_return("ok\n")

      result = described_class.run_deno_command("install", "--frozen=false", dir: dir)
      expect(result).to eq("ok\n")
    end

    it "propagates HelperSubprocessFailed on non-zero exit" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "boom",
            error_context: { command: "deno install" }
          )
        )

      expect do
        described_class.run_deno_command("install", dir: dir)
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /boom/)
    end
  end
end
