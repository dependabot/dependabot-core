# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/helpers"

RSpec.describe Dependabot::Deno::Helpers do
  describe ".run_deno_command" do
    let(:dir) { "/tmp/some-dir" }

    it "invokes deno with the given args in the given dir and returns combined output" do
      allow(Open3).to receive(:capture2e)
        .with({ "DENO_DIR" => anything }, "deno", "install", "--frozen=false", chdir: dir)
        .and_return(["ok\n", instance_double(Process::Status, success?: true, exitstatus: 0)])

      result = described_class.run_deno_command("install", "--frozen=false", dir: dir)
      expect(result).to eq("ok\n")
    end

    it "raises with combined output on non-zero exit" do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture2e).and_return(["error: boom\n", status])

      expect do
        described_class.run_deno_command("install", dir: dir)
      end.to raise_error(Dependabot::Deno::Helpers::DenoCommandError, /error: boom/)
    end
  end
end
