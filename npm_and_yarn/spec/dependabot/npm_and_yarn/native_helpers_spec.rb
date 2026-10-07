# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"

RSpec.describe Dependabot::NpmAndYarn::NativeHelpers do
  describe ".run_pnpm_audit_fix_command" do
    before do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command) do |command, **|
        command == "-v" ? pnpm_version : ""
      end
    end

    context "with pnpm 11" do
      let(:pnpm_version) { "Corepack warning\n11.25.0\n" }

      it "uses the lockfile update fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix=update", fingerprint: "audit --fix=update")
      end
    end

    context "with pnpm 10" do
      let(:pnpm_version) { "10.16.0" }

      it "uses the compatible override fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix", fingerprint: "audit --fix")
      end
    end
  end
end
