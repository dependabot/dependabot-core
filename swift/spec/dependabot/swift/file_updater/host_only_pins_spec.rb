# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/swift/file_updater/host_only_pins"

RSpec.describe Dependabot::Swift::FileUpdater::HostOnlyPins do
  subject(:host_only_pins) { described_class.new(committed: committed, resolved_on_host: resolved_on_host) }

  let(:swift_log_pin) do
    {
      "identity" => "swift-log",
      "kind" => "remoteSourceControl",
      "location" => "https://github.com/apple/swift-log.git",
      "state" => { "revision" => "3ffafb9722d5d918c614feb496c8789a3b59d222", "version" => "1.15.0" }
    }
  end
  let(:opencombine_pin) do
    {
      "identity" => "opencombine",
      "kind" => "remoteSourceControl",
      "location" => "https://github.com/OpenCombine/OpenCombine.git",
      "state" => { "revision" => "8576f0d579b27020beccbccc3ea6844f3ddfc2c2", "version" => "0.14.0" }
    }
  end
  let(:resolved_on_host) { swiftpm_json("pins" => [opencombine_pin, swift_log_pin], "version" => 2) }

  def swiftpm_json(data)
    "#{JSON.pretty_generate(data, space_before: ' ')}\n"
  end

  context "when the committed Package.resolved uses version 1 of the format" do
    let(:committed) do
      swiftpm_json(
        "object" => {
          "pins" => [{
            "package" => "swift-log",
            "repositoryURL" => "https://github.com/apple/swift-log",
            "state" => { "branch" => nil, "revision" => "a878e7f8f46cfc0e1125e565b5c08e7d5272dc9a",
                         "version" => "1.14.0" }
          }]
        },
        "version" => 1
      )
    end

    it "finds the pins it does not have, comparing locations without case or a .git suffix" do
      expect(host_only_pins.keys).to eq(["https://github.com/opencombine/opencombine"])
    end

    it "leaves those pins out" do
      expect(host_only_pins.remove_from(resolved_on_host))
        .to eq(swiftpm_json("pins" => [swift_log_pin], "version" => 2))
    end
  end

  context "when the committed Package.resolved has every pin" do
    let(:committed) { resolved_on_host }

    it "returns the content as it is" do
      content = resolved_on_host.sub("\n}\n", "\n}")

      expect(host_only_pins.keys).to be_empty
      expect(host_only_pins.remove_from(content)).to equal(content)
    end
  end
end
