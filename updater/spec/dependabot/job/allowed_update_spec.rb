# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job/allowed_update"

RSpec.describe Dependabot::Job::AllowedUpdate do
  describe ".from_hash" do
    context "with default values" do
      it "parses a minimal hash" do
        update = described_class.from_hash({})
        expect(update.dependency_name).to be_nil
        expect(update.dependency_type).to eq("all")
        expect(update.update_type).to eq("all")
        expect(update.update_types).to eq([])
        expect(update.prerelease).to be_nil
      end
    end

    context "with prerelease: true" do
      it "parses the prerelease field" do
        update = described_class.from_hash({
          "dependency-name" => "MyCompany.*",
          "prerelease" => true
        })
        expect(update.dependency_name).to eq("MyCompany.*")
        expect(update.prerelease).to be(true)
      end
    end

    context "with prerelease: false" do
      it "parses the prerelease field as false" do
        update = described_class.from_hash({
          "dependency-name" => "Some.Package",
          "prerelease" => false
        })
        expect(update.prerelease).to be(false)
      end
    end

    context "without prerelease key" do
      it "defaults prerelease to nil" do
        update = described_class.from_hash({
          "dependency-name" => "Some.Package"
        })
        expect(update.prerelease).to be_nil
      end
    end
  end

  describe "#to_hash" do
    context "when prerelease is nil" do
      it "omits prerelease from the hash" do
        update = described_class.from_hash({ "dependency-name" => "Some.Package" })
        hash = update.to_hash
        expect(hash).not_to have_key("prerelease")
      end
    end

    context "when prerelease is true" do
      it "includes prerelease in the hash" do
        update = described_class.from_hash({
          "dependency-name" => "MyCompany.*",
          "prerelease" => true
        })
        hash = update.to_hash
        expect(hash["prerelease"]).to be(true)
        expect(hash["dependency-name"]).to eq("MyCompany.*")
      end
    end

    context "when prerelease is false" do
      it "includes prerelease as false in the hash" do
        update = described_class.from_hash({
          "dependency-name" => "Some.Package",
          "prerelease" => false
        })
        hash = update.to_hash
        expect(hash["prerelease"]).to be(false)
      end
    end
  end

  describe "round-trip serialization" do
    it "preserves the prerelease flag through from_hash and to_hash" do
      original = {
        "dependency-name" => "MyCompany.*",
        "dependency-type" => "all",
        "update-type" => "all",
        "prerelease" => true
      }
      update = described_class.from_hash(original)
      result = update.to_hash

      expect(result["dependency-name"]).to eq("MyCompany.*")
      expect(result["prerelease"]).to be(true)
    end
  end
end
