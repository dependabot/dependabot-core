# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/requirement_parser"

RSpec.describe Dependabot::GoModules::RequirementParser do
  describe ".parse" do
    subject(:parsed) { described_class.parse(dependency_string) }

    context "with a standard module@version string" do
      let(:dependency_string) { "golang.org/x/tools@v0.28.0" }

      it "parses name, version, and requirement" do
        expect(parsed).to eq(
          {
            name: "golang.org/x/tools",
            normalised_name: "golang.org/x/tools",
            version: "0.28.0",
            requirement: "v0.28.0",
            extras: nil,
            language: "golang",
            registry: nil
          }
        )
      end
    end

    context "with a github module path" do
      let(:dependency_string) { "github.com/stretchr/testify@v1.9.0" }

      it "parses correctly" do
        expect(parsed[:name]).to eq("github.com/stretchr/testify")
        expect(parsed[:version]).to eq("1.9.0")
        expect(parsed[:requirement]).to eq("v1.9.0")
      end
    end

    context "with a major version in path (v5)" do
      let(:dependency_string) { "github.com/go-chi/chi/v5@v5.1.0" }

      it "parses the full module path including major version" do
        expect(parsed[:name]).to eq("github.com/go-chi/chi/v5")
        expect(parsed[:version]).to eq("5.1.0")
        expect(parsed[:requirement]).to eq("v5.1.0")
      end
    end

    context "with a pre-release version" do
      let(:dependency_string) { "github.com/some/module@v2.0.0-rc1" }

      it "parses the pre-release version" do
        expect(parsed[:name]).to eq("github.com/some/module")
        expect(parsed[:version]).to eq("2.0.0-rc1")
        expect(parsed[:requirement]).to eq("v2.0.0-rc1")
      end
    end

    context "with a pseudo-version" do
      let(:dependency_string) { "golang.org/x/net@v0.0.0-20240101120000-abcdef123456" }

      it "parses the pseudo-version" do
        expect(parsed[:name]).to eq("golang.org/x/net")
        expect(parsed[:version]).to eq("0.0.0-20240101120000-abcdef123456")
        expect(parsed[:requirement]).to eq("v0.0.0-20240101120000-abcdef123456")
      end
    end

    context "with a +incompatible suffix" do
      let(:dependency_string) { "github.com/old/lib@v3.2.1+incompatible" }

      it "parses the version with +incompatible" do
        expect(parsed[:name]).to eq("github.com/old/lib")
        expect(parsed[:version]).to eq("3.2.1+incompatible")
        expect(parsed[:requirement]).to eq("v3.2.1+incompatible")
      end
    end

    context "with a v0 unstable version" do
      let(:dependency_string) { "github.com/pkg/errors@v0.9.1" }

      it "parses the v0 version" do
        expect(parsed[:name]).to eq("github.com/pkg/errors")
        expect(parsed[:version]).to eq("0.9.1")
        expect(parsed[:requirement]).to eq("v0.9.1")
      end
    end

    context "with a deeply nested module path" do
      let(:dependency_string) { "cloud.google.com/go/storage@v1.43.0" }

      it "parses the nested path" do
        expect(parsed[:name]).to eq("cloud.google.com/go/storage")
        expect(parsed[:version]).to eq("1.43.0")
      end
    end

    context "with minimal patch version" do
      let(:dependency_string) { "golang.org/x/text@v0.3.0" }

      it "parses correctly" do
        expect(parsed[:name]).to eq("golang.org/x/text")
        expect(parsed[:version]).to eq("0.3.0")
        expect(parsed[:requirement]).to eq("v0.3.0")
      end
    end

    context "with whitespace around the string" do
      let(:dependency_string) { "  golang.org/x/tools@v0.28.0  " }

      it "strips whitespace and parses correctly" do
        expect(parsed[:name]).to eq("golang.org/x/tools")
        expect(parsed[:version]).to eq("0.28.0")
      end
    end

    context "with mixed case module path" do
      let(:dependency_string) { "github.com/Azure/azure-sdk-for-go@v1.0.0" }

      it "normalises the name to lowercase" do
        expect(parsed[:name]).to eq("github.com/Azure/azure-sdk-for-go")
        expect(parsed[:normalised_name]).to eq("github.com/azure/azure-sdk-for-go")
      end
    end

    context "with a module path without version (no @)" do
      let(:dependency_string) { "golang.org/x/tools" }

      it "returns nil" do
        expect(parsed).to be_nil
      end
    end

    context "with an empty string" do
      let(:dependency_string) { "" }

      it "returns nil" do
        expect(parsed).to be_nil
      end
    end

    context "with a simple package name (not a module path)" do
      let(:dependency_string) { "somepackage@v1.0.0" }

      it "returns nil (not a valid Go module path)" do
        expect(parsed).to be_nil
      end
    end

    context "with a Python-style dependency string" do
      let(:dependency_string) { "types-requests==2.31.0.10" }

      it "returns nil" do
        expect(parsed).to be_nil
      end
    end

    context "with only @ and no version" do
      let(:dependency_string) { "golang.org/x/tools@" }

      it "returns nil" do
        expect(parsed).to be_nil
      end
    end
  end
end
