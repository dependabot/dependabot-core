# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/error_details"

RSpec.describe Dependabot::ErrorDetails do
  it "parses and serializes hash details" do
    details = described_class.from_hash(
      {
        "error-type": "dependency_file_not_found",
        "error-detail": { message: "missing" }
      }
    )

    expect(details).to have_attributes(
      error_type: "dependency_file_not_found",
      error_detail: { message: "missing" }
    )
    expect(details.to_h).to eq(
      "error-type": "dependency_file_not_found",
      "error-detail": { message: "missing" }
    )
  end

  it "supports string and nil details" do
    expect(
      described_class.from_hash("error-type": "unknown", "error-detail": "boom").error_detail
    ).to eq("boom")
    expect(described_class.from_hash("error-type": "unknown").error_detail).to be_nil
  end

  it "rejects malformed error types" do
    expect { described_class.from_hash("error-type": 1) }.to raise_error(TypeError)
  end
end
