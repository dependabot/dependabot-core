# typed: false
# frozen_string_literal: true

require "spec_helper"
require "wildcard_matcher"

RSpec.describe WildcardMatcher do
  describe ".match?" do
    subject { described_class.match?(wildcard_string, candidate_string) }

    context "without a wildcard" do
      let(:wildcard_string) { "bus" }

      context "with a matching string" do
        let(:candidate_string) { wildcard_string }

        it { is_expected.to be(true) }

        context "with different capitalisation" do
          let(:candidate_string) { "Bus" }

          it { is_expected.to be(true) }
        end
      end

      context "with a superstring" do
        let(:candidate_string) { wildcard_string + "iness" }

        it { is_expected.to be(false) }
      end

      context "with a substring" do
        let(:candidate_string) { "bu" }

        it { is_expected.to be(false) }
      end

      context "with a string that ends in the same way" do
        let(:candidate_string) { "blunderbus" }

        it { is_expected.to be(false) }
      end

      context "with a regex character" do
        let(:wildcard_string) { "bus." }

        context "with a matching string" do
          let(:candidate_string) { wildcard_string }

          it { is_expected.to be(true) }
        end

        context "with a superstring" do
          let(:candidate_string) { wildcard_string + "iness" }

          it { is_expected.to be(false) }
        end
      end
    end

    context "with a wildcard" do
      context "when the wildcard is at the start" do
        let(:wildcard_string) { "*bus" }

        context "with a matching string" do
          let(:candidate_string) { wildcard_string }

          it { is_expected.to be(true) }
        end

        context "with a matching string (except the wildcard" do
          let(:candidate_string) { "bus" }

          it { is_expected.to be(true) }
        end

        context "with a string that ends in the same way" do
          let(:candidate_string) { "blunderbus" }

          it { is_expected.to be(true) }
        end

        context "with a superstring" do
          let(:candidate_string) { wildcard_string + "iness" }

          it { is_expected.to be(false) }
        end

        context "with a substring" do
          let(:candidate_string) { "bu" }

          it { is_expected.to be(false) }
        end
      end

      context "when the wildcard is at the end" do
        let(:wildcard_string) { "bus*" }

        context "with a matching string" do
          let(:candidate_string) { wildcard_string }

          it { is_expected.to be(true) }
        end

        context "with a matching string (except the wildcard" do
          let(:candidate_string) { "bus" }

          it { is_expected.to be(true) }
        end

        context "with a string that ends in the same way" do
          let(:candidate_string) { "blunderbus" }

          it { is_expected.to be(false) }
        end

        context "with a superstring" do
          let(:candidate_string) { wildcard_string + "iness" }

          it { is_expected.to be(true) }
        end

        context "with a substring" do
          let(:candidate_string) { "bu" }

          it { is_expected.to be(false) }
        end
      end

      context "when the wildcard is in the middle" do
        let(:wildcard_string) { "bu*s" }

        context "with a matching string" do
          let(:candidate_string) { wildcard_string }

          it { is_expected.to be(true) }
        end

        context "with a matching string (except the wildcard" do
          let(:candidate_string) { "bus" }

          it { is_expected.to be(true) }
        end

        context "with a string that ends in the same way" do
          let(:candidate_string) { "blunderbus" }

          it { is_expected.to be(false) }
        end

        context "with a superstring" do
          let(:candidate_string) { wildcard_string + "y" }

          it { is_expected.to be(false) }
        end

        context "with a substring" do
          let(:candidate_string) { "bu" }

          it { is_expected.to be(false) }
        end

        context "with a string that starts and ends in the right way" do
          let(:candidate_string) { "business" }

          it { is_expected.to be(true) }
        end
      end

      context "when the wildcard is the only character" do
        let(:wildcard_string) { "*" }

        context "with a matching string" do
          let(:candidate_string) { wildcard_string }

          it { is_expected.to be(true) }
        end

        context "with any string" do
          let(:candidate_string) { "bus" }

          it { is_expected.to be(true) }
        end
      end

      context "with multiple wildcards" do
        let(:wildcard_string) { "bu*in*ss" }

        context "with a string that fits" do
          let(:candidate_string) { "business" }

          it { is_expected.to be(true) }
        end

        context "with a string that doesn't" do
          let(:candidate_string) { "buspass" }

          it { is_expected.to be(false) }
        end
      end
    end
  end
end
