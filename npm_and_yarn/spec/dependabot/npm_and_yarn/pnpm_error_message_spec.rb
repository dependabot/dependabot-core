# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/pnpm_error_message"

RSpec.describe Dependabot::NpmAndYarn::PnpmErrorMessage do
  describe ".normalize" do
    subject(:normalized) { described_class.normalize(message) }

    def pnpm_error(version, name)
      fixture("pnpm_errors", version, "#{name}.txt")
    end

    context "with a pnpm 12 registry error whose URL is wrapped mid-token" do
      let(:message) { pnpm_error("pnpm12", "private_tarball_urls") }

      it "rewrites the block into pnpm 11's layout and rejoins the URL" do
        expect(normalized.lines.first.chomp).to eq(
          "[ERR_PNPM_FETCH_401] Failed to resolve dependency tree: " \
          "GET https://npm.pkg.github.com/@dsp-testing%2Finner-source-top-secret-npm-2: Unauthorized - 401"
        )
      end

      it "keeps the remaining paragraphs on their own lines without borders" do
        expect(normalized.lines.map(&:chomp)).to include(
          "Failed to resolve @dsp-testing/inner-source-top-secret-npm-2@1.0.3",
          "No authorization header was set for the request."
        )
        expect(normalized).not_to match(/[×│├╰]/)
      end
    end

    context "when a wrap falls on a slash" do
      let(:message) { pnpm_error("pnpm12", "nonexistent_dependency_yanked_version") }

      it "joins the pieces without adding a space" do
        expect(normalized).to include(
          "GET https://registry.npmjs.org/@dependabot%2Ftotally-fake-dependency-soz: Not Found - 404"
        )
      end

      it "joins a help paragraph wrapped at a space with a single space" do
        expect(normalized).to include(
          "@dependabot/totally-fake-dependency-soz is not in the npm registry, or you have no permission to fetch it."
        )
      end
    end

    context "with output printed before the error block" do
      let(:message) { pnpm_error("pnpm12", "private_repo_no_access") }

      it "keeps the preceding lines unchanged" do
        expect(normalized.lines.first).to start_with('[WARN] Ignored project-level auth setting "//npm.pkg.github.com/')
        expect(normalized).to include("[ERR_PNPM_FETCH_404] Failed to resolve dependency tree: GET https://npm.pkg.github.com/@dsp-testing%2Fnode")
      end
    end

    context "with a pnpm 12 error that has no ERR_PNPM code" do
      let(:message) { pnpm_error("pnpm12", "missing_workspace_dir_package") }

      it "unwraps the text without adding a code" do
        expect(normalized.lines.first.chomp).to eq(
          "Failed to resolve dependency tree: Failed to resolve dependency: " \
          'Could not install from "/tmp/npm/pkg" as it does not exist.'
        )
      end
    end

    context "with a lockfile version that pnpm 12 can't read" do
      let(:message) { pnpm_error("pnpm12", "old_lockfile_v6") }

      it "rejoins the wrapped sentence" do
        expect(normalized).to include(
          "is broken: The lockfileVersion of 6.0 is incompatible with this version of pnpm, " \
          "which supports lockfileVersion 9.x (1:18)"
        )
        expect(normalized).to start_with("[ERR_PNPM_BROKEN_LOCKFILE] The lockfile at ")
      end
    end

    context "with a pnpm 11 message" do
      let(:message) { pnpm_error("pnpm11", "private_package_access") }

      it "returns it unchanged" do
        expect(normalized).to eq(message)
      end
    end

    context "with text that only starts with Error:" do
      let(:message) { "Error: something went wrong\nwhile doing it" }

      it "returns it unchanged" do
        expect(normalized).to eq(message)
      end
    end
  end
end
