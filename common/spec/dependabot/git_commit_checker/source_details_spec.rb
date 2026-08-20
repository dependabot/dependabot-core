# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_commit_checker/source_details"

RSpec.describe Dependabot::GitCommitChecker::SourceDetails do
  describe ".from_hash" do
    subject(:source_details) { described_class.from_hash(details) }

    context "with symbol keys" do
      let(:details) do
        {
          type: "git",
          url: "https://github.com/dependabot/dependabot-core",
          branch: "main",
          ref: "v1.0.0"
        }
      end

      it "parses the known fields" do
        expect(source_details).to have_attributes(
          type: "git",
          url: "https://github.com/dependabot/dependabot-core",
          branch: "main",
          ref: "v1.0.0"
        )
      end
    end

    context "with string keys" do
      let(:details) do
        {
          "type" => "git",
          "url" => "https://github.com/dependabot/dependabot-core",
          "branch" => "main",
          "ref" => "v1.0.0"
        }
      end

      it "parses the known fields" do
        expect(source_details).to have_attributes(
          type: "git",
          url: "https://github.com/dependabot/dependabot-core",
          branch: "main",
          ref: "v1.0.0"
        )
      end
    end

    context "with non-string values" do
      let(:details) do
        {
          type: true,
          url: 1,
          branch: [],
          ref: {}
        }
      end

      it "drops them" do
        expect(source_details).to have_attributes(type: nil, url: nil, branch: nil, ref: nil)
      end
    end
  end
end
