# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"
require "spec_helper"
require "dependabot/maven/native_helpers"

RSpec.describe Dependabot::Maven::NativeHelpers do
  describe "handle_tool_error" do
    context "when the output contains a 403 error" do
      let(:output) { "Could not transfer artifact com.example:example:jar:1.0.0 from/to example-repo (https://example.com/repo): status code: 403" }

      it "raises PrivateSourceAuthenticationFailure for 401 and 403 errors" do
        expect do
          described_class.handle_tool_error(output)
        end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when the output contains a 401 error" do
      let(:output) { "Could not transfer artifact com.example:example:jar:1.0.0 from/to example-repo (https://example.com/repo): status code: 401" }

      it "raises PrivateSourceAuthenticationFailure for 401 and 403 errors" do
        expect do
          described_class.handle_tool_error(output)
        end.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    it "raises DependabotError for other errors" do
      output = "Some other error occurred"
      expect do
        described_class.handle_tool_error(output)
      end.to raise_error(Dependabot::DependabotError)
    end
  end
end
