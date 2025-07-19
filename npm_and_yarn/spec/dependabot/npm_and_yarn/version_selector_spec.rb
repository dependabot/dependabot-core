# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/version_selector"

RSpec.describe Dependabot::NpmAndYarn::VersionSelector do
  describe "#setup" do
    let(:manifest_json) { { "engines" => engines } }
    let(:name) { "pnpm" }
    let(:selector) { described_class.new }

    context "with versions containing special characters" do
      it "strips special characters from version strings" do
        # Test with a caret version
        engines = { "pnpm" => "^10.2.3" }
        expect(selector.setup({ "engines" => engines }, "pnpm")).to eq({ "pnpm" => "10.2.3" })
      end
    end
  end
end
