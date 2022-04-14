# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/type_script_library"

RSpec.describe Dependabot::NpmAndYarn::TypeScriptLibrary do
  describe "#types_package" do
    it "returns the corresponding types package name" do
      lodash       = "lodash"
      lodash_types = "@types/lodash"

      types_package = described_class.new(lodash).types_package

      expect(types_package).to eq(lodash_types)
    end

    it "returns the input if it is already a types package" do
      stereo_types = "@types/stereo"

      types_package = described_class.new(stereo_types).types_package

      expect(types_package).to eq(stereo_types)
    end

    it "trusts users to have meaningful package names" do
      expect(described_class.new("🤷").types_package).to eq("@types/🤷")
      expect(described_class.new([]).types_package).to eq("@types/[]")
      expect(described_class.new({}).types_package).to eq("@types/{}")
    end

    context "when given a scoped dependency name" do
      it "returns the corresponding scoped types package name" do
        babel_core       = "@babel/core"
        babel_core_types = "@types/babel__core"

        types_package = described_class.new(babel_core).types_package

        expect(types_package).to eq(babel_core_types)
      end
    end

    context "when the input is unmappable" do
      it "returns an empty string" do
        expect(described_class.new(nil).types_package).to eq("")
        expect(described_class.new("").types_package).to eq("")
        expect(described_class.new("NOT_A_DEPENDENCY").types_package).to eq("")
        expect(described_class.new("@types/NOT_A_TYPES_DEFINITION").types_package).to eq("")
        expect(described_class.new(" prefixed-with-a-space").types_package).to eq("")
        expect(described_class.new(".prefixed-with-a-dot").types_package).to eq("")
        expect(described_class.new("!invalid").types_package).to eq("")
      end
    end
  end
end
