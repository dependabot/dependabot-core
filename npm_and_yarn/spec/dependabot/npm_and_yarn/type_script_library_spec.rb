# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/type_script_library"

RSpec.describe Dependabot::NpmAndYarn::TypeScriptLibrary do
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
  describe "#types_package" do
    it "returns the corresponding types package name" do
      lodash       = "lodash"
      lodash_types = "@types/lodash"

      types_package = described_class.new(lodash).types_package

      expect(types_package).to eq(lodash_types)
    end

    it "returns nil if it is already a types package" do
      stereo_types = "@types/stereo"

      types_package = described_class.new(stereo_types).types_package

      expect(types_package).to be_nil
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
end
