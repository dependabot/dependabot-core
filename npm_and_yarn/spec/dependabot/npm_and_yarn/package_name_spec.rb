# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/package_name"

RSpec.describe Dependabot::NpmAndYarn::PackageName do
  describe "initialization" do
    it "raises a meaningful error if the input is not a valid package name" do
      expect { described_class.new("🤷") }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new([]) }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new({}) }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new(nil) }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new("") }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new(" prefixed-with-a-space") }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new(".prefixed-with-a-dot") }.to raise_error(described_class::InvalidPackageName)
      expect { described_class.new("!invalid") }.to raise_error(described_class::InvalidPackageName)
    end
  end

  describe "#to_s" do
    it "returns the name when no scope is present" do
      jquery = "jquery"

      package_name = described_class.new(jquery).to_s

      expect(package_name).to eq(jquery)
    end

    it "returns the name with scope when a scope is present" do
      babel_core = "@babel/core"

      package_name_with_scope = described_class.new(babel_core).to_s

      expect(package_name_with_scope).to eq(babel_core)
    end
  end

  describe "#types_package" do
    it "returns the corresponding types package name" do
      lodash       = "lodash"
      lodash_types = "@types/lodash"

      types_package = described_class.new(lodash).types_package

      expect(types_package).to eq(lodash_types)
    end

    it "returns self if it is already a types package" do
      stereo_types = "@types/stereo"

      types_package = described_class.new(stereo_types).types_package

      expect(types_package.to_s).to eq(stereo_types)
    end

    context "when given a scoped dependency name" do
      it "returns the corresponding scoped types package name" do
        babel_core       = "@babel/core"
        babel_core_types = "@types/babel__core"

        types_package = described_class.new(babel_core).types_package

        expect(types_package).to eq(babel_core_types)
      end
    end
  end

  describe "#<=>" do
    it "provides affordances for sorting/comparison" do
      first  = described_class.new("first")
      second = described_class.new("second")
      third  = described_class.new("third")

      expect([third, second, first].sort).to eq([first, second, third])
    end

    it "allows for comparison with types packages" do
      library = described_class.new("my-library")

      expect([library, library.types_package].sort).to eq([library.types_package, library])
    end
  end
end
