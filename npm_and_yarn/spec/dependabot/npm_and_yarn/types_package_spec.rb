# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/types_package"

RSpec.describe Dependabot::NpmAndYarn::TypesPackage do
  describe "#library" do
    it "returns the corresponding dependency name" do
      jquery_types = "@types/jquery"
      jquery       = "jquery"

      library = described_class.new(jquery_types).library

      expect(library).to eq(jquery)
    end

    it "trusts users to have meaningful package names" do
      expect(described_class.new("@types/🤷").library).to eq("🤷")
      expect(described_class.new("@types/[]").library).to eq("[]")
      expect(described_class.new("@types/{}").library).to eq("{}")
    end


    context "when given a scoped type definition dependency name" do
      it "returns the corresponding scoped dependency name" do
        babel_core_types = "@types/babel__core"
        babel_core       = "@babel/core"

        library = described_class.new(babel_core_types).library

        expect(library).to eq(babel_core)
      end
    end

    context "when the input cannot be translated" do
      it "returns an empty string" do
        expect(described_class.new("").library).to eq("")
        expect(described_class.new("@types/").library).to eq("")
        expect(described_class.new("@types/NOT_A_TYPES_DEFINITION").library).to eq("")
        expect(described_class.new("@types/ prefixed-with-a-space").library).to eq("")
        expect(described_class.new("@types/.prefixed-with-a-dot").library).to eq("")
        expect(described_class.new("@types/!invalid").library).to eq("")
      end
    end
  end
end
