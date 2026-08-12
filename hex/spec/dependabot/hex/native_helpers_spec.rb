# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/native_helpers"

RSpec.describe Dependabot::Hex::NativeHelpers do
  let(:helper_paths) do
    Dir.glob(File.join(described_class.hex_helpers_dir, "lib/*.exs"))
  end

  it "does not depend on removed hidden APIs" do
    forbidden_apis = [
      /\bMix\.Dep(?:\.|\b)/,
      /\bMix\.SCM\.(?:Git|Path)\b/,
      /\bHex\.(?:SCM|Mix|Utils)\b/
    ]

    aggregate_failures do
      helper_paths.product(forbidden_apis).each do |path, forbidden_api|
        expect(File.read(path)).not_to match(forbidden_api), "#{path} references #{forbidden_api.inspect}"
      end
    end
  end
end
