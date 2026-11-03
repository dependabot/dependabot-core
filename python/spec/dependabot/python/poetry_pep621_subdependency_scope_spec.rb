# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/poetry_pep621_subdependency_scope"

RSpec.describe Dependabot::Python::PoetryPep621SubdependencyScope do
  describe ".pins_for_dependency" do
    subject(:pins) { described_class.pins_for_dependency(lockfile, "colorama", "colorama==0.4.6") }

    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "poetry.lock",
        content: <<~TOML
          [[package]]
          name = "colorama"
          version = "0.4.4"
          optional = #{optional}
          #{marker_line}
        TOML
      )
    end
    let(:marker_line) { "" }
    let(:optional) { false }

    context "when the package isn't in the lockfile" do
      let(:lockfile) { nil }

      it "pins unconditionally in main" do
        expect(pins).to eq(["colorama==0.4.6", {}])
      end
    end

    context "when the package is not optional and has no marker" do
      it "pins unconditionally in main" do
        expect(pins).to eq(["colorama==0.4.6", {}])
      end
    end

    context "when the package is not optional and mixes an environment branch with an extra branch" do
      let(:marker_line) { 'markers = "sys_platform == \"win32\" or extra == \"lint\""' }

      it "pins in main with the full marker verbatim, and nowhere else" do
        expect(pins).to eq(['colorama==0.4.6; sys_platform == "win32" or extra == "lint"', {}])
      end
    end

    context "when the package is optional and needed by several extras" do
      let(:optional) { true }
      let(:marker_line) { 'markers = "extra == \"lint\" or extra == \"test\""' }

      it "pins in each extra with the full marker, and not in main" do
        marker = 'extra == "lint" or extra == "test"'

        expect(pins).to eq([nil, { "lint" => "colorama==0.4.6; #{marker}", "test" => "colorama==0.4.6; #{marker}" }])
      end
    end

    context "when the package is optional but the lockfile records no markers" do
      let(:optional) { true }

      it "leaves it unpinned rather than promoting it into main" do
        expect(pins).to eq([nil, {}])
      end
    end

    context "when markers are keyed by group" do
      let(:optional) { true }
      let(:marker_line) { 'markers = { main = "extra == \"lint\"", dev = "extra == \"test\"" }' }

      it "pins each extra with the marker string that names it" do
        expect(pins).to eq(
          [nil, { "lint" => 'colorama==0.4.6; extra == "lint"', "test" => 'colorama==0.4.6; extra == "test"' }]
        )
      end
    end
  end
end
