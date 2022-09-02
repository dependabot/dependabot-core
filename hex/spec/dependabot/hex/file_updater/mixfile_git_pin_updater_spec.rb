# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/file_updater/mixfile_git_pin_updater"

RSpec.describe Dependabot::Hex::FileUpdater::MixfileGitPinUpdater do
  let(:updater) do
    described_class.new(
      mixfile_content: mixfile_content,
      dependency_name: "phoenix",
      previous_pin: previous_pin,
      updated_pin: updated_pin
    )
  end

  let(:mixfile_content) do
    fixture("mixfiles", mixfile_fixture_name)
  end
  let(:mixfile_fixture_name) { "git_source_tag_can_update" }
  let(:previous_pin) { "v1.2.0" }
  let(:updated_pin) { "v1.3.0" }

  describe "#updated_content" do
    subject(:updated_content) { updater.updated_content }

    it "updates the right dependency" do
      expect(updated_content).to include(%({:plug, "1.3.3"},))
      expect(updated_content).to include(
        %({:phoenix, github: "dependabot-fixtures/phoenix", ref: "v1.3.0"})
      )
    end

    context "specified over multiple lines" do
      let(:mixfile_fixture_name) { "git_source_multiple_lines" }

      it "updates the right dependency" do
        expect(updated_content).to include(%({:plug, "1.3.3"},))
        expect(updated_content).to include(
          "{:phoenix,\n" \
          '       github: "dependabot-fixtures/phoenix", tag: "v1.3.0"}'
        )
      end
    end
  end
end
