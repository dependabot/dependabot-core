# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pre_commit/additional_dependency_checkers"
require "dependabot/pre_commit/additional_dependency_checkers/base"

RSpec.describe Dependabot::PreCommit::AdditionalDependencyCheckers do
  describe ".register and .for_language" do
    let(:mock_checker_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyCheckers::Base) do
        def latest_version
          nil
        end

        def updated_requirements(_latest_version)
          []
        end
      end
    end

    before do
      described_class.register("test_language", mock_checker_class)
    end

    it "returns the registered checker for a language" do
      expect(described_class.for_language("test_language")).to eq(mock_checker_class)
    end

    it "is case-insensitive" do
      expect(described_class.for_language("Test_Language")).to eq(mock_checker_class)
      expect(described_class.for_language("TEST_LANGUAGE")).to eq(mock_checker_class)
    end

    it "raises for unsupported languages" do
      expect { described_class.for_language("unsupported") }.to raise_error(
        /Unsupported language for additional_dependencies: unsupported/
      )
    end
  end

  describe ".supported?" do
    let(:mock_checker_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyCheckers::Base) do
        def latest_version
          nil
        end

        def updated_requirements(_latest_version)
          []
        end
      end
    end

    before do
      described_class.register("test_language", mock_checker_class)
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
    let(:mock_checker_class) do
      Class.new(Dependabot::PreCommit::AdditionalDependencyCheckers::Base) do
        def latest_version
          nil
        end

        def updated_requirements(_latest_version)
          []
        end
      end
    end

    before do
      described_class.register("language_a", mock_checker_class)
      described_class.register("language_b", mock_checker_class)
    end

    it "returns all registered languages" do
      languages = described_class.supported_languages
      expect(languages).to include("language_a")
      expect(languages).to include("language_b")
    end
  end

  describe "built-in language support" do
    it "supports python" do
      expect(described_class.supported?("python")).to be true
    end

    it "supports node" do
      expect(described_class.supported?("node")).to be true
    end

    it "supports golang" do
      expect(described_class.supported?("golang")).to be true
    end

    it "supports rust" do
      expect(described_class.supported?("rust")).to be true
    end

    it "supports dart" do
      expect(described_class.supported?("dart")).to be true
    end
  end
end
