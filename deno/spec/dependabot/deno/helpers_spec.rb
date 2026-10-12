# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/deno/helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Deno::Helpers do
  describe ".parse_json_or_jsonc" do
    it "returns an empty hash for nil content" do
      expect(described_class.parse_json_or_jsonc(nil)).to eq({})
    end

    it "parses JSON with comments and trailing commas" do
      content = <<~JSONC
        {
          // a line comment
          /* a block comment */
          "imports": {
            "@std/path": "jsr:@std/path@^1.0.0",
          },
        }
      JSONC
      expect(described_class.parse_json_or_jsonc(content))
        .to eq("imports" => { "@std/path" => "jsr:@std/path@^1.0.0" })
    end

    it "raises a clear error when the top-level value is not an object" do
      expect do
        described_class.parse_json_or_jsonc("[1, 2, 3]")
      end.to raise_error(JSON::ParserError, /Expected a JSON object/)
    end
  end

  describe ".safe_relative_path?" do
    it "accepts repo-relative paths" do
      expect(described_class.safe_relative_path?("packages/alpha")).to be(true)
    end

    it "rejects empty paths" do
      expect(described_class.safe_relative_path?("")).to be(false)
    end

    it "rejects absolute paths" do
      expect(described_class.safe_relative_path?("/etc")).to be(false)
    end

    it "rejects paths containing traversal segments" do
      expect(described_class.safe_relative_path?("packages/../../etc")).to be(false)
      expect(described_class.safe_relative_path?("../outside")).to be(false)
    end
  end

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
