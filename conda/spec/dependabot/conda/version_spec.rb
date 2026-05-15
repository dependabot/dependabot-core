# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/version"

RSpec.describe Dependabot::Conda::Version do
  subject(:version) { described_class.new(version_string) }

  describe ".correct?" do
    it "accepts standard numeric versions" do
      expect(described_class.correct?("1.0.0")).to be(true)
      expect(described_class.correct?("2.3.4")).to be(true)
      expect(described_class.correct?("3.14")).to be(true)
      expect(described_class.correct?("5")).to be(true)
    end

    it "accepts versions with letter suffixes (tzdata-style)" do
      expect(described_class.correct?("2020a")).to be(true)
      expect(described_class.correct?("2020d")).to be(true)
      expect(described_class.correct?("2021e")).to be(true)
      expect(described_class.correct?("2025b")).to be(true)
    end

    it "accepts versions with build strings" do
      expect(described_class.correct?("1.0.0_0")).to be(true)
      expect(described_class.correct?("2.1_py39h1234567_0")).to be(true)
      expect(described_class.correct?("3.0-build123")).to be(true)
    end

    it "accepts PEP 440 style pre-releases" do
      expect(described_class.correct?("1.0.0a1")).to be(true)
      expect(described_class.correct?("1.0.0.dev0")).to be(true)
      expect(described_class.correct?("2.0.0rc1")).to be(true)
    end

    it "accepts versions with epochs" do
      expect(described_class.correct?("1!1.0.0")).to be(true)
    end

    it "rejects invalid version strings" do
      expect(described_class.correct?("")).to be(false)
      expect(described_class.correct?(nil)).to be(false)
    end
  end

  describe "#to_s" do
    context "with a standard version" do
      let(:version_string) { "1.2.3" }

      it { expect(version.to_s).to eq("1.2.3") }
    end

    context "with a letter suffix version (tzdata)" do
      let(:version_string) { "2025b" }

      it { expect(version.to_s).to eq("2025b") }
    end

    context "with a build string" do
      let(:version_string) { "1.0.0_0" }

      it { expect(version.to_s).to eq("1.0.0_0") }
    end

    context "with a prerelease version" do
      let(:version_string) { "1.2.3a1" }

      it { expect(version.to_s).to eq("1.2.3a1") }
    end

    context "with an epoch" do
      let(:version_string) { "1!1.2.3" }

      it { expect(version.to_s).to eq("1!1.2.3") }
    end
  end

  describe "comparisons" do
    it "correctly compares standard versions" do
      expect(described_class.new("1.0.0")).to be < described_class.new("1.0.1")
      expect(described_class.new("1.0.1")).to be > described_class.new("1.0.0")
      expect(described_class.new("2.0")).to be > described_class.new("1.9.9")
    end

    it "correctly identifies equal versions" do
      version1 = described_class.new("1.0.0")
      version2 = described_class.new("1.0.0")
      expect(version1).to eq(version2)
      expect(version1).to eql(version2)
    end

    it "correctly compares letter suffixes (tzdata-style)" do
      expect(described_class.new("2020a")).to be < described_class.new("2020b")
      expect(described_class.new("2020d")).to be > described_class.new("2020a")
      expect(described_class.new("2021a")).to be > described_class.new("2020z")
      expect(described_class.new("2025a")).to be < described_class.new("2025b")
    end

    it "correctly compares versions with different segment counts" do
      expect(described_class.new("1.0")).to be < described_class.new("1.0.1")
      expect(described_class.new("2.0.0")).to eq(described_class.new("2.0"))
      expect(described_class.new("3")).to be < described_class.new("3.0.1")
      expect(described_class.new("3.0")).to eq(described_class.new("3"))
    end

    it "compares prerelease versions" do
      expect(described_class.new("1.0.0a1")).to be < described_class.new("1.0.0a2")
      expect(described_class.new("1.0.0rc1")).to be > described_class.new("1.0.0a1")
    end

    # Category 1: Epoch comparison
    describe "epoch comparison" do
      it "compares epochs numerically first" do
        expect(described_class.new("1!1.0")).to be > described_class.new("2.0")
        expect(described_class.new("2!0.1")).to be > described_class.new("1!9.9")
      end

      it "treats missing epoch as epoch 0" do
        expect(described_class.new("0!1.0")).to eq(described_class.new("1.0"))
        expect(described_class.new("1!1.0")).to be > described_class.new("0!2.0")
      end

      it "compares version when epochs are equal" do
        expect(described_class.new("1!2.0")).to be > described_class.new("1!1.0")
        expect(described_class.new("2!1.5")).to be < described_class.new("2!2.0")
      end
    end

    # Category 2: Pre-release ordering (dev)
    describe "dev pre-release ordering" do
      it "sorts dev before all other pre-releases" do
        expect(described_class.new("1.0dev")).to be < described_class.new("1.0a1")
        expect(described_class.new("1.0dev1")).to be < described_class.new("1.0a1")
        expect(described_class.new("1.0dev1")).to be < described_class.new("1.0")
      end

      it "sorts dev versions among themselves" do
        expect(described_class.new("1.0dev")).to be < described_class.new("1.0dev1")
        expect(described_class.new("1.0dev1")).to be < described_class.new("1.0dev2")
      end

      it "handles full dev pre-release sequence" do
        expect(described_class.new("1.0dev1")).to be < described_class.new("1.0dev2")
        expect(described_class.new("1.0dev2")).to be < described_class.new("1.0a1")
        expect(described_class.new("1.0a1")).to be < described_class.new("1.0")
      end
    end

    # Category 3: Post-release ordering
    describe "post-release ordering" do
      it "sorts post after main version" do
        expect(described_class.new("1.0")).to be < described_class.new("1.0post")
        expect(described_class.new("1.0")).to be < described_class.new("1.0post1")
      end

      it "sorts post versions among themselves" do
        expect(described_class.new("1.0post")).to be < described_class.new("1.0post1")
        expect(described_class.new("1.0post1")).to be < described_class.new("1.0post2")
      end

      it "handles full release sequence" do
        expect(described_class.new("1.0dev1")).to be < described_class.new("1.0a1")
        expect(described_class.new("1.0a1")).to be < described_class.new("1.0")
        expect(described_class.new("1.0")).to be < described_class.new("1.0post1")
      end
    end

    # Category 4: Fillvalue insertion
    describe "fillvalue insertion" do
      it "treats missing numeric segments as 0" do
        expect(described_class.new("1.1")).to eq(described_class.new("1.1.0"))
        expect(described_class.new("1")).to eq(described_class.new("1.0"))
      end

      it "compares with fillvalue correctly" do
        expect(described_class.new("1.1.0")).to be < described_class.new("1.1.0.1")
        expect(described_class.new("1.1")).to be < described_class.new("1.1.0.1")
      end
    end

    # Category 5: Local versions
    describe "local versions" do
      it "compares local versions when main versions are equal" do
        version_local = described_class.new("1.0+local")
        expect(version_local).to eq(described_class.new("1.0+local"))
        version_abc = described_class.new("1.0+abc")
        expect(version_abc).to eq(described_class.new("1.0+abc"))
        expect(described_class.new("1.0+a")).to be < described_class.new("1.0+b")
        expect(described_class.new("1.0+local.1")).to be > described_class.new("1.0+local")
      end

      it "sorts version without local before version with local" do
        expect(described_class.new("1.0")).to be < described_class.new("1.0+local")
      end

      it "ignores local version when main versions differ" do
        expect(described_class.new("1.0+zzz")).to be < described_class.new("1.1+aaa")
        expect(described_class.new("2.0+local")).to be > described_class.new("1.9+local")
      end
    end

    # Category 6: Case-insensitive comparison
    describe "case-insensitive comparison" do
      it "treats uppercase and lowercase as equal" do
        expect(described_class.new("1.0A1")).to eq(described_class.new("1.0a1"))
        expect(described_class.new("1.0.RC1")).to eq(described_class.new("1.0.rc1"))
        expect(described_class.new("1.0.Alpha")).to eq(described_class.new("1.0.alpha"))
      end

      it "compares case-insensitively" do
        expect(described_class.new("1.0.A")).to be < described_class.new("1.0.B")
        expect(described_class.new("1.0.a")).to be < described_class.new("1.0.B")
        expect(described_class.new("1.0.A")).to be < described_class.new("1.0.b")
      end
    end

    # Category 7: Underscore normalization
    describe "underscore normalization" do
      it "treats underscores as dots" do
        expect(described_class.new("1.0_1")).to eq(described_class.new("1.0.1"))
        expect(described_class.new("1_0_0")).to eq(described_class.new("1.0.0"))
        expect(described_class.new("2_1")).to eq(described_class.new("2.1"))
      end

      it "compares normalized versions correctly" do
        expect(described_class.new("1.0_1")).to be < described_class.new("1.0.2")
        expect(described_class.new("1_0")).to be < described_class.new("1.0.1")
      end
    end

    # Category 8: Mixed-type segment ordering
    describe "mixed-type segment ordering" do
      it "sorts integers before strings in mixed-type comparison" do
        # Integer < String (this is the conda spec)
        # Numeric versions sort before pre-release versions
        expect(described_class.new("1.0.0")).to be < described_class.new("1.0.0a")
        expect(described_class.new("1.0.1")).to be < described_class.new("1.0.a")
      end

      it "handles complex mixed-type comparisons" do
        expect(described_class.new("1.0.0")).to be < described_class.new("1.0.0alpha")
        expect(described_class.new("2.0")).to be < described_class.new("2.rc1")
      end
    end

    # Real-world examples from conda spec
    describe "conda spec examples" do
      it "handles the canonical example sequence" do
        versions = [
          "1.0dev1",
          "1.0a1",
          "1.0",
          "1.0post1"
        ].map { |v| described_class.new(v) }

        # Verify the ordering is correct
        expect(versions[0]).to be < versions[1] # dev < alpha
        expect(versions[1]).to be < versions[2] # alpha < release
        expect(versions[2]).to be < versions[3] # release < post
      end

      it "verifies epoch dominance" do
        expect(described_class.new("1!1.0")).to be > described_class.new("2.0")
      end

      it "verifies local version behavior" do
        expect(described_class.new("1.0+local")).to be < described_class.new("1.0+local.1")
      end
    end
  end

  describe "validation" do
    it "rejects versions with empty segments" do
      expect { described_class.new("1..2") }.to raise_error(ArgumentError, /Empty version segments/)
      expect { described_class.new(".1.2") }.to raise_error(ArgumentError, /Empty version segments/)
      expect { described_class.new("1.2.") }.to raise_error(ArgumentError, /Empty version segments/)
    end

    it "accepts valid versions" do
      expect { described_class.new("1.2.3") }.not_to raise_error
      expect { described_class.new("1!2.0+local") }.not_to raise_error
      expect { described_class.new("1.0dev1") }.not_to raise_error
    end
  end
end
