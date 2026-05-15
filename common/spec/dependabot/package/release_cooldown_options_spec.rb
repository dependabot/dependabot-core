# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/release_cooldown_options"

RSpec.describe Dependabot::Package::ReleaseCooldownOptions do
  subject(:release_cooldown_options) do
    described_class.new(
      default_days: default_days,
      semver_major_days: semver_major_days,
      semver_minor_days: semver_minor_days,
      semver_patch_days: semver_patch_days,
      include: include_list,
      exclude: exclude_list
    )
  end

  let(:default_days) { 7 }
  let(:semver_major_days) { 10 }
  let(:semver_minor_days) { 5 }
  let(:semver_patch_days) { 2 }
  let(:include_list) { ["*", "package-a"] }
  let(:exclude_list) { ["package-b"] }

  describe "#semver_major_days" do
    it "returns semver_major_days when set" do
      expect(release_cooldown_options.semver_major_days).to eq(10)
    end

    context "when semver_major_days is zero" do
      let(:semver_major_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.semver_major_days).to eq(7)
      end
    end
  end

  describe "#semver_minor_days" do
    it "returns semver_minor_days when set" do
      expect(release_cooldown_options.semver_minor_days).to eq(5)
    end

    context "when semver_minor_days is zero" do
      let(:semver_minor_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.semver_minor_days).to eq(7)
      end
    end
  end

  describe "#semver_patch_days" do
    it "returns semver_patch_days when set" do
      expect(release_cooldown_options.semver_patch_days).to eq(2)
    end

    context "when semver_patch_days is zero" do
      let(:semver_patch_days) { 0 }

      it "falls back to default_days" do
        expect(release_cooldown_options.semver_patch_days).to eq(7)
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

  describe "#cooldown_days_for" do
    context "with distinct semver days" do
      let(:default_days) { 5 }
      let(:semver_major_days) { 14 }
      let(:semver_minor_days) { 7 }
      let(:semver_patch_days) { 2 }

      it "returns semver_major_days for a major bump" do
        expect(release_cooldown_options.cooldown_days_for([1, 0, 0], [2, 0, 0])).to eq(14)
      end

      it "returns semver_minor_days for a minor bump" do
        expect(release_cooldown_options.cooldown_days_for([1, 0, 0], [1, 1, 0])).to eq(7)
      end

      it "returns semver_patch_days for a patch bump" do
        expect(release_cooldown_options.cooldown_days_for([1, 0, 0], [1, 0, 1])).to eq(2)
      end

      it "returns default_days when versions are equal" do
        expect(release_cooldown_options.cooldown_days_for([1, 0, 0], [1, 0, 0])).to eq(5)
      end

      it "returns default_days when current_semver is nil" do
        expect(release_cooldown_options.cooldown_days_for(nil, [2, 0, 0])).to eq(5)
      end

      it "returns default_days when new_semver is nil" do
        expect(release_cooldown_options.cooldown_days_for([1, 0, 0], nil)).to eq(5)
      end

      it "returns default_days when both are nil" do
        expect(release_cooldown_options.cooldown_days_for(nil, nil)).to eq(5)
      end

      it "returns semver_major_days for a major bump that also changes minor and patch" do
        expect(release_cooldown_options.cooldown_days_for([0, 33, 0], [1, 2, 3])).to eq(14)
      end

      it "returns default_days for a downgrade (new major < current major)" do
        expect(release_cooldown_options.cooldown_days_for([2, 0, 0], [1, 5, 0])).to eq(5)
      end

      it "returns default_days for a minor downgrade within the same major" do
        expect(release_cooldown_options.cooldown_days_for([1, 5, 0], [1, 3, 0])).to eq(5)
      end

      it "returns default_days for a patch downgrade within the same major and minor" do
        expect(release_cooldown_options.cooldown_days_for([1, 5, 3], [1, 5, 1])).to eq(5)
      end

      it "returns semver_minor_days when major is equal and minor increases" do
        expect(release_cooldown_options.cooldown_days_for([2, 1, 0], [2, 3, 0])).to eq(7)
      end
    end
  end
end
