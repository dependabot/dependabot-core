# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "dependabot/apm/native_helpers"

RSpec.describe Dependabot::Apm::NativeHelpers do
  describe ".run_apm_command" do
    around do |example|
      Dir.mktmpdir do |dir|
        apm = File.join(dir, "apm", "bin", "apm")
        FileUtils.mkdir_p(File.dirname(apm))
        # A successful command that also logs a diagnostic, as APM does for
        # policy discovery and upgrade notices.
        File.write(apm, <<~SH)
          #!/bin/sh
          echo 'WARNING apm_cli.policy.discovery Policy repo not found' >&2
          echo '[{"target": "claude", "status": "inactive"}]'
        SH
        File.chmod(0o755, apm)
        original = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        ENV["DEPENDABOT_NATIVE_HELPERS_PATH"] = dir
        example.run
      ensure
        ENV["DEPENDABOT_NATIVE_HELPERS_PATH"] = original
      end
    end

    it "includes stderr in the output by default" do
      expect(described_class.run_apm_command("targets --json --all")).to include("WARNING")
    end

    it "returns only stdout when stderr_to_stdout is false" do
      output = described_class.run_apm_command("targets --json --all", stderr_to_stdout: false)

      expect(JSON.parse(output)).to eq([{ "target" => "claude", "status" => "inactive" }])
    end
  end
end
