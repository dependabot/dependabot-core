# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_parsers"
require "dependabot/pre_commit/additional_dependency_parsers/base"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyParsers do
  describe ".register and .for_language" do
    let(:mock_parser_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyParsers::Base) do
        def parse
          nil
        end
      end
    end

    before do
      described_class.register("test_language", mock_parser_class)
    end

    it "returns the registered parser for a language" do
      expect(described_class.for_language("test_language")).to eq(mock_parser_class)
    end

    it "is case-insensitive" do
      expect(described_class.for_language("Test_Language")).to eq(mock_parser_class)
      expect(described_class.for_language("TEST_LANGUAGE")).to eq(mock_parser_class)
    end

    it "raises for unsupported languages" do
      expect { described_class.for_language("unsupported") }.to raise_error(
        /Unsupported language for additional_dependencies parsing: unsupported/
      )
    end
  end

  describe ".supported?" do
    let(:mock_parser_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyParsers::Base) do
        def parse
          nil
        end
      end
    end

    before do
      described_class.register("test_language", mock_parser_class)
    end

    it "returns true for registered languages" do
      expect(described_class.supported?("test_language")).to be true
    end

    it "is case-insensitive" do
      expect(described_class.supported?("Test_Language")).to be true
    end

    it "returns false for unsupported languages" do
      expect(described_class.supported?("unsupported")).to be false
    end
  end

  describe ".supported_languages" do
    let(:mock_parser_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyParsers::Base) do
        def parse
          nil
        end
      end
    end

    before do
      described_class.register("language_a", mock_parser_class)
      described_class.register("language_b", mock_parser_class)
    end

    it "returns all registered languages" do
      languages = described_class.supported_languages
      expect(languages).to include("language_a")
      expect(languages).to include("language_b")
    end
  end
end
