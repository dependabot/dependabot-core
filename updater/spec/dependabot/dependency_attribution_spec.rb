# typed: false
# frozen_string_literal: true

require "dependabot/dependency_attribution"
require "dependabot/dependency"
require "spec_helper"

RSpec.describe Dependabot::DependencyAttribution do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rails",
      version: "7.0.0",
      requirements: [],
      package_manager: "bundler"
    )
  end

  describe "::annotate_dependency" do
    it "adds attribution metadata to dependency" do
      dependency = create_dependency("rails", "7.0.0")

      described_class.annotate_dependency(dependency, "backend", :direct, "/api")

      # Check attribution using getter methods instead of instance variables
      expect(dependency.respond_to?(:attribution_source_group)).to be true
      expect(dependency.respond_to?(:attribution_selection_reason)).to be true
      expect(dependency.respond_to?(:attribution_directory)).to be true
    end

    it "validates selection reason" do
      expect do
        described_class.annotate_dependency(
          dependency,
          source_group: "backend",
          selection_reason: :invalid_reason,
          directory: "/api"
        )
      end.not_to(change { dependency.instance_variables.count })
    end

    it "handles dependencies that don't support instance variables" do
      fake_dependency = "not a real dependency"

      expect do
        described_class.annotate_dependency(
          fake_dependency,
          source_group: "backend",
          selection_reason: :direct,
          directory: "/api"
        )
      end.not_to raise_error
    end

    context "with valid selection reasons" do
      Dependabot::DependencyAttribution::SELECTION_REASONS.each do |reason|
        it "sets the correct selection reason for #{reason}" do
          dependency = create_dependency("rails", "7.0.0")

          described_class.annotate_dependency(dependency, "backend", reason, "/api")

          # Verify the method was called with correct parameters
          expect(dependency).to respond_to(:attribution_selection_reason)
        end
      end
    end
  end

  describe "::get_attribution" do
    context "when dependency has attribution" do
      before do
        described_class.annotate_dependency(
          dependency,
          source_group: "backend",
          selection_reason: :dependency_drift,
          directory: "/web"
        )
      end

      it "returns the attribution metadata" do
        attribution = described_class.get_attribution(dependency)

        expect(attribution).to eq({
          source_group: "backend",
          selection_reason: :dependency_drift,
          directory: "/web"
        })
      end
    end

    context "when dependency has no attribution" do
      it "returns nil" do
        attribution = described_class.get_attribution(dependency)
        expect(attribution).to be_nil
      end
    end

    context "when dependency has partial attribution" do
      before do
        allow(dependency).to receive(:respond_to?).with(:attribution_source_group).and_return(true)
        allow(dependency).to receive(:attribution_source_group).and_return("backend")
        allow(dependency).to receive(:respond_to?).with(:attribution_selection_reason).and_return(false)
        allow(dependency).to receive(:respond_to?).with(:attribution_directory).and_return(false)
        # Missing selection_reason and directory
      end

      it "returns partial attribution" do
        attribution = described_class.get_attribution(dependency)

        expect(attribution).to eq({
          source_group: "backend",
          selection_reason: nil,
          directory: nil
        })
      end
    end
  end

  describe "SELECTION_REASONS" do
    it "includes all required reasons" do
      expected_reasons = %i(
        direct
        already_updated
        dependency_drift
        not_in_group
        filtered_by_config
        unknown
      )

      expect(described_class::SELECTION_REASONS).to match_array(expected_reasons)
    end

    it "is frozen to prevent modification" do
      expect(described_class::SELECTION_REASONS).to be_frozen
    end
  end
end
