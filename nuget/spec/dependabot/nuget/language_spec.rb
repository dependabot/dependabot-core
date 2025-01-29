# typed: false
# frozen_string_literal: true

require "dependabot/nuget/language"
require "dependabot/nuget/requirement"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Nuget::Language do
  describe "#initialize" do
    context "when version and requirement are both strings initially" do
      let(:language) { Dependabot::Nuget::CSharpLanguage.new(name) }
      let(:name) { "cs-dotnet472" }

      it "sets the name correctly" do
        expect(language.name).to eq("cs-dotnet472")
      end
    end

    context "when version and requirement are both strings initially" do
      let(:language) { Dependabot::Nuget::VBLanguage.new(name) }
      let(:name) { "vb-net35" }

      it "sets the name correctly" do
        expect(language.name).to eq("vb-net35")
      end
    end

    context "when version and requirement are both strings initially" do
      let(:language) { Dependabot::Nuget::FSharpLanguage.new(name) }
      let(:name) { "fs-netstandard1.5" }

      it "sets the name correctly" do
        expect(language.name).to eq("fs-netstandard1.5")
      end
    end
  end
end
