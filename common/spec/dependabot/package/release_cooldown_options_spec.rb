# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Package::ReleaseCooldownOptions do
  subject(:release_cooldown_options) do
    described_class.new(
      default_days: default_days,
      major_days: major_days,
      minor_days: minor_days,
      patch_days: patch_days,
      include: include_list,
      exclude: exclude_list
    )
  end

  let(:default_days) { 7 }
  let(:major_days) { 10 }
  let(:minor_days) { 5 }
  let(:patch_days) { 2 }
  let(:include_list) { ["*", "package-a"] }
  let(:exclude_list) { ["package-b"] }

  describe "#major_days" do
    it "returns major_days when set" do
      expect(release_cooldown_options.major_days).to eq(10)
    end

    context "when major_days is zero" do
      let(:major_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.major_days).to eq(7)
      end
    end
  end

  describe "#minor_days" do
    it "returns minor_days when set" do
      expect(release_cooldown_options.minor_days).to eq(5)
    end

    context "when minor_days is zero" do
      let(:minor_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.minor_days).to eq(7)
      end
    end
  end

  describe "#patch_days" do
    it "returns patch_days when set" do
      expect(release_cooldown_options.patch_days).to eq(2)
    end

    context "when patch_days is zero" do
      let(:patch_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.patch_days).to eq(7)
      end
    end
  end

  describe "#included?" do
    [nil, [], ["*"]].each do |include_item|
      context "when include list is set to #{include_item.inspect}" do
        let(:include_list) { include_item }

        [nil, []].each do |exclude_item| # rubocop:disable Performance/CollectionLiteralInLoop
          context "when exclude list is set to #{exclude_item.inspect}" do
            let(:exclude_list) { exclude_item }

            it "returns true for any dependency" do
              expect(release_cooldown_options.included?("package-a")).to be true
              expect(release_cooldown_options.included?("package-b")).to be true
              expect(release_cooldown_options.included?("random-package")).to be true
            end
          end
        end

        context "when exclude list is set to ['*']" do
          let(:exclude_list) { ["*"] }

          it "returns always false for all dependencies" do
            expect(release_cooldown_options.included?("package-a")).to be false
            expect(release_cooldown_options.included?("package-b")).to be false
            expect(release_cooldown_options.included?("random-package")).to be false
          end
        end

        context "when exclude list is set to ['package-*']" do
          let(:exclude_list) { ["package-*"] }

          it "returns true for dependencies not matching exclude pattern" do
            expect(release_cooldown_options.included?("another-package-a")).to be true
          end

          it "returns false for dependencies matching exclude pattern" do
            expect(release_cooldown_options.included?("package-b")).to be false
            expect(release_cooldown_options.included?("package-c")).to be false
          end
        end

        context "when exclude list is set to ['package-a']" do
          let(:exclude_list) { ["package-a"] } # Excludes only "package-a"

          it "returns false for dependencies explicitly in the exclude list" do
            expect(release_cooldown_options.included?("package-a")).to be false
          end

          it "returns true for dependencies not in the exclude list" do
            expect(release_cooldown_options.included?("another-package")).to be true
          end

          it "returns true for dependencies with similar names" do
            expect(release_cooldown_options.included?("package-ab")).to be true
          end
        end
      end
    end

    context "when include list is set to ['package-*']" do
      let(:include_list) { ["package-*"] }

      [nil, []].each do |exclude_item|
        context "when exclude list is set to #{exclude_item.inspect}" do
          let(:exclude_list) { exclude_item }

          it "returns true only if package starts with 'package-'" do
            expect(release_cooldown_options.included?("package-a")).to be true
            expect(release_cooldown_options.included?("package-b")).to be true
          end

          it "returns false for dependencies not starting with 'package-'" do
            expect(release_cooldown_options.included?("package")).to be false
            expect(release_cooldown_options.included?("another-package")).to be false
          end
        end
      end

      context "when exclude list is set to ['*']" do
        let(:exclude_list) { ["*"] }

        it "returns always false for all dependencies" do
          expect(release_cooldown_options.included?("package")).to be false
          expect(release_cooldown_options.included?("package-a")).to be false
          expect(release_cooldown_options.included?("random-package")).to be false
        end
      end

      context "when exclude list is set to ['package-ex*']" do
        let(:exclude_list) { ["another-*"] }

        it "returns true for dependencies not matching exclude pattern" do
          expect(release_cooldown_options.included?("package-")).to be true
          expect(release_cooldown_options.included?("package-test")).to be true
        end

        it "returns false for dependencies matching exclude pattern" do
          expect(release_cooldown_options.included?("another-ex")).to be false
          expect(release_cooldown_options.included?("another-exclude")).to be false
        end
      end

      context "when exclude list is set to ['package-a']" do
        let(:exclude_list) { ["package-a"] } # Excludes only "package-a"

        it "returns true for dependencies not in the exclude list" do
          expect(release_cooldown_options.included?("package-b")).to be true
        end

        it "returns false for dependencies explicitly in the exclude list" do
          expect(release_cooldown_options.included?("package-a")).to be false
        end
      end
    end

    context "when include list is set to ['package-a']" do
      let(:include_list) { %w(package-a package-b) }

      [nil, []].each do |exclude_item|
        context "when exclude list is set to #{exclude_item.inspect}" do
          let(:exclude_list) { exclude_item }

          it "returns true only if package is in include list" do
            expect(release_cooldown_options.included?("package-a")).to be true
            expect(release_cooldown_options.included?("package-b")).to be true
          end

          it "returns false for dependencies not in include list" do
            expect(release_cooldown_options.included?("package")).to be false
            expect(release_cooldown_options.included?("another-package")).to be false
          end
        end
      end

      context "when exclude list is set to ['*']" do
        let(:exclude_list) { ["*"] }

        it "returns always false for all dependencies" do
          expect(release_cooldown_options.included?("package")).to be false
          expect(release_cooldown_options.included?("package-a")).to be false
          expect(release_cooldown_options.included?("random-package")).to be false
        end
      end

      context "when exclude list is set to ['package-ex*']" do
        let(:exclude_list) { ["another-*"] }

        it "returns true only if package is in include list and not matching exclude pattern" do
          expect(release_cooldown_options.included?("package-a")).to be true
          expect(release_cooldown_options.included?("package-b")).to be true
        end

        it "returns false for dependencies not in include list" do
          expect(release_cooldown_options.included?("package")).to be false
          expect(release_cooldown_options.included?("another-package")).to be false
        end

        it "returns false if dependency is matching exclude pattern" do
          expect(release_cooldown_options.included?("package-ex")).to be false
          expect(release_cooldown_options.included?("package-exclude")).to be false
        end
      end

      context "when exclude list is set to ['package-a']" do
        let(:exclude_list) { ["package-a"] } # Excludes only "package-a"

        it "returns true if dependency is in include list and not in exclude list" do
          expect(release_cooldown_options.included?("package-b")).to be true
        end

        it "returns false if dependency is in include list and in exclude list" do
          expect(release_cooldown_options.included?("package-a")).to be false
        end

        it "returns false if dependency is not in include list" do
          expect(release_cooldown_options.included?("package")).to be false
        end
      end
    end
  end
end
