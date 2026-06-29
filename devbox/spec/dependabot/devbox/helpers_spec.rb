# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/devbox/helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Devbox::Helpers do
  describe ".parse_json_or_jsonc" do
    it "returns an empty hash for nil content" do
      expect(described_class.parse_json_or_jsonc(nil)).to eq({})
    end

    it "parses JSON with comments and trailing commas" do
      content = <<~JSONC
        {
          // a line comment
          /* a block comment */
          "packages": [
            "python@3.10",
            "ripgrep@latest",
          ],
        }
      JSONC
      expect(described_class.parse_json_or_jsonc(content))
        .to eq("packages" => ["python@3.10", "ripgrep@latest"])
    end

    it "does not treat // inside a string value as a comment" do
      content = <<~JSONC
        {
          "$schema": "https://raw.githubusercontent.com/jetify-com/devbox/0.13.0/.schema/devbox.schema.json"
        }
      JSONC
      expect(described_class.parse_json_or_jsonc(content))
        .to eq(
          "$schema" => "https://raw.githubusercontent.com/jetify-com/devbox/0.13.0/.schema/devbox.schema.json"
        )
    end

    it "raises a clear error when the top-level value is not an object" do
      expect do
        described_class.parse_json_or_jsonc("[1, 2, 3]")
      end.to raise_error(JSON::ParserError, /Expected a JSON object/)
    end
  end

  describe ".run_devbox_command" do
    let(:dir) { "/tmp/some-dir" }

    it "delegates to SharedHelpers.run_shell_command with a scoped cache" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          "devbox update python",
          cwd: dir,
          env: hash_including("DEVBOX_CACHE" => "#{dir}/.devbox_cache")
        )
        .and_return("ok\n")

      result = described_class.run_devbox_command("update", "python", dir: dir)
      expect(result).to eq("ok\n")
    end

    it "propagates HelperSubprocessFailed on non-zero exit" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "boom",
            error_context: { command: "devbox update" }
          )
        )

      expect do
        described_class.run_devbox_command("update", dir: dir)
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /boom/)
    end
  end
end
