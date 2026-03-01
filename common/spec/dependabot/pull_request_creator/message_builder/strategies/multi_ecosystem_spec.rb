# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pull_request_creator/message_builder/strategies/multi_ecosystem"

namespace = Dependabot::PullRequestCreator::MessageBuilder
RSpec.describe namespace::Strategies::MultiEcosystem do
  subject(:strategy) do
    described_class.new(group_name: group_name, update_count: update_count)
  end

  let(:group_name) { "my-dependencies" }
  let(:update_count) { 3 }

  describe "#base_title" do
    it "returns the multi-ecosystem title with plural updates" do
      expect(strategy.base_title).to eq(
        "bump the \"my-dependencies\" group with 3 updates across multiple ecosystems"
      )
    end

    context "with a single update" do
      let(:update_count) { 1 }

      it "returns singular update" do
        expect(strategy.base_title).to eq(
          "bump the \"my-dependencies\" group with 1 update across multiple ecosystems"
        )
      end
    end

    context "with a different group name" do
      let(:group_name) { "security-patches" }

      it "uses the group name" do
        expect(strategy.base_title).to eq(
          "bump the \"security-patches\" group with 3 updates across multiple ecosystems"
        )
      end
    end
  end
end
