# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/update_checker/version_details"

RSpec.describe Dependabot::Bundler::UpdateChecker::VersionDetails do
  describe ".from_helper_result" do
    subject(:details) { described_class.from_helper_result(result) }

    let(:result) do
      {
        "version" => "1.5.0",
        "ruby_version" => "3.3.0",
        "fetcher" => "Bundler::Fetcher::CompactIndex",
        "commit_sha" => "abc123",
        "unknown" => { "future" => true }
      }
    end

    it "parses the known fields without changing the response" do
      result.freeze

      expect(details).to have_attributes(
        version: Dependabot::Bundler::Version.new("1.5.0"),
        ruby_version: "3.3.0",
        fetcher: "Bundler::Fetcher::CompactIndex",
        commit_sha: "abc123"
      )
      expect(details.version).to be_a(Dependabot::Bundler::Version)
      expect(result["version"]).to eq("1.5.0")
    end

    context "with only a version" do
      let(:result) { { "version" => "1.5.0" } }

      it "leaves optional fields absent" do
        expect(details).to have_attributes(ruby_version: nil, fetcher: nil, commit_sha: nil)
      end
    end

    context "with null optional fields" do
      let(:result) { super().merge("ruby_version" => nil, "fetcher" => nil, "commit_sha" => nil) }

      it "preserves nil" do
        expect(details).to have_attributes(ruby_version: nil, fetcher: nil, commit_sha: nil)
      end
    end

    context "with a version that RubyGems normalises" do
      let(:result) { super().merge("version" => "1.5.0-beta") }

      it "retains the original version text for registry lookups" do
        expect(details.version.to_s).to eq("1.5.0.pre.beta")
        expect(details.version.to_semver).to eq("1.5.0-beta")
      end
    end

    context "with empty optional strings" do
      let(:result) { super().merge("ruby_version" => "", "fetcher" => "", "commit_sha" => "") }

      it "does not coerce them to nil" do
        expect(details).to have_attributes(ruby_version: "", fetcher: "", commit_sha: "")
      end
    end

    [nil, [], "invalid", 1, false].each do |value|
      context "with #{value.inspect} in place of an object" do
        let(:result) { value }

        it "reports a non-retryable helper failure" do
          expect { details }.to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed,
            "resolve_version result must be an object"
          ) do |error|
            expect(error.error_class).to eq("TypeError")
            expect(error.error_context).to eq(function: "resolve_version")
          end
        end
      end
    end

    context "without a version" do
      let(:result) { super().except("version") }

      it "identifies the required field" do
        expect { details }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          "resolve_version result.version must be a string"
        )
      end
    end

    [
      ["version", nil],
      ["version", 1],
      ["version", []],
      ["ruby_version", false],
      ["fetcher", {}],
      ["commit_sha", 1]
    ].each do |field, value|
      context "with #{field} set to #{value.inspect}" do
        let(:result) { super().merge(field => value) }

        it "identifies the malformed field" do
          expect { details }.to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed,
            /resolve_version result\.#{field} must be a string/
          )
        end
      end
    end

    context "with an invalid version string" do
      let(:result) { super().merge("version" => "not-a-version") }

      it "does not expose the invalid value in the helper failure" do
        expect { details }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          "resolve_version result.version must be a valid version"
        ) do |error|
          expect(error.cause).to be_nil
        end
      end
    end

    context "with a non-string key" do
      let(:result) { super().merge(unknown: true) }

      it "rejects the malformed object" do
        expect { details }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          "resolve_version result keys must be strings"
        )
      end
    end
  end
end
