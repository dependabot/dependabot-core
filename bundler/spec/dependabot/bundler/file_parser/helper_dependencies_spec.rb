# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/file_parser/helper_dependencies"

RSpec.describe Dependabot::Bundler::FileParser::HelperDependencies do
  gemfile_record = Dependabot::Bundler::FileParser::HelperDependencies::GemfileDependency
  gemspec_record = Dependabot::Bundler::FileParser::HelperDependencies::GemspecDependency
  invalid_results = [nil, {}, "invalid"]
  invalid_entries = [nil, [], "invalid"]
  required_fields = %w(name requirement source)
  invalid_fields = [["name", 1], ["requirement", false], ["source", []]]

  [
    [:from_gemfile_result, "parsed_gemfile", "Gemfile", gemfile_record],
    [:from_gemspec_result, "parsed_gemspec", "example.gemspec", gemspec_record]
  ].each do |factory, operation, filename, record_class|
    describe ".#{factory}" do
      subject(:dependencies) { described_class.public_send(factory, result, file: file) }

      let(:file) { Dependabot::DependencyFile.new(name: filename, content: "") }
      let(:record) do
        {
          "name" => "business",
          "requirement" => "~> 1.4.0",
          "groups" => ["default"],
          "source" => nil,
          "type" => "runtime",
          "unconsumed" => { "arbitrary" => true }
        }
      end
      let(:result) { [record] }

      it "returns operation-specific records" do
        expect(dependencies.first).to be_a(record_class)
        expect(dependencies.first).to have_attributes(name: "business", requirement: "~> 1.4.0", source: nil)
      end

      context "with an empty result" do
        let(:result) { [] }

        it "returns no dependencies" do
          expect(dependencies).to be_empty
        end
      end

      context "with repeated entries" do
        let(:result) { [record, record.merge("name" => "statesman"), record] }

        it "preserves order and duplicates" do
          expect(dependencies.map(&:name)).to eq(%w(business statesman business))
        end
      end

      context "with an empty requirement" do
        let(:record) { super().merge("requirement" => "") }

        it "does not normalize the requirement" do
          expect(dependencies.first.requirement).to eq("")
        end
      end

      context "with a Git source" do
        let(:record) do
          super().merge("source" => { "type" => "git", "url" => "git@example.com:repo", "branch" => nil, "ref" => "" })
        end

        it "preserves source keys and null values while symbolizing keys" do
          expect(dependencies.first.source).to eq(type: "git", url: "git@example.com:repo", branch: nil, ref: "")
        end
      end

      context "with a registry source" do
        let(:record) { super().merge("source" => { "type" => "rubygems", "url" => "https://gems.example/" }) }

        it "does not add absent Git fields" do
          expect(dependencies.first.source).to eq(type: "rubygems", url: "https://gems.example/")
        end
      end

      context "with another string source type" do
        let(:record) { super().merge("source" => { "type" => "metadata" }) }

        it "does not impose a new source-type enum" do
          expect(dependencies.first.source).to eq(type: "metadata")
        end
      end

      invalid_results.each do |value|
        context "with #{value.inspect} as the result" do
          let(:result) { value }

          it "identifies the operation and file" do
            expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
              expect(error.message).to include(operation, file.path, "must be an array")
            end
          end
        end
      end

      invalid_entries.each do |value|
        context "with #{value.inspect} as an entry" do
          let(:result) { [record, value] }

          it "rejects the complete result with entry context" do
            expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
              expect(error.message).to include(operation, file.path, "[1]", "must be an object")
            end
          end
        end
      end

      required_fields.each do |field|
        context "without #{field}" do
          let(:record) { super().except(field) }

          it "reports the missing consumed field" do
            expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /#{field}/)
          end
        end
      end

      invalid_fields.each do |field, value|
        context "with malformed #{field}" do
          let(:record) { super().merge(field => value) }

          it "does not coerce the value" do
            expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /#{field}/)
          end
        end
      end

      context "with a missing source type" do
        let(:record) { super().merge("source" => { "url" => "https://gems.example/" }) }

        it "reports the source type" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /source.type/)
        end
      end

      context "with a malformed source field" do
        let(:record) { super().merge("source" => { "type" => "git", "url" => ["do-not-echo-this"] }) }

        it "identifies the field without echoing its contents" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable) do |error|
            expect(error.message).to include("source.url")
            expect(error.message).not_to include("do-not-echo-this")
          end
        end
      end

      context "with non-string source keys" do
        let(:record) { super().merge("source" => { "type" => "git", 1 => "invalid" }) }

        it "reports the key shape" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /keys must be strings/)
        end
      end
    end
  end

  describe ".from_gemfile_result groups" do
    subject(:dependencies) { described_class.from_gemfile_result(result, file: file) }

    let(:file) { Dependabot::DependencyFile.new(name: "Gemfile", content: "") }
    let(:groups) { %w(development test development) }
    let(:result) { [{ "name" => "business", "requirement" => ">= 0", "groups" => groups, "source" => nil }] }

    it "preserves group ordering without requiring the unused type field" do
      expect(dependencies.first.groups).to eq(groups)
    end

    [nil, "default", [1]].each do |value|
      context "with groups set to #{value.inspect}" do
        let(:groups) { value }

        it "rejects the malformed groups" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /groups/)
        end
      end
    end
  end

  describe ".from_gemspec_result type" do
    subject(:dependencies) { described_class.from_gemspec_result(result, file: file) }

    let(:file) { Dependabot::DependencyFile.new(name: "example.gemspec", content: "") }
    let(:type) { "runtime" }
    let(:result) do
      [{ "name" => "business", "requirement" => ">= 0", "groups" => nil, "source" => nil, "type" => type }]
    end

    it "accepts null groups without carrying them into the typed result" do
      expect(dependencies.first.type).to eq("runtime")
    end

    context "with a different string type" do
      let(:type) { "other" }

      it "does not impose a new dependency-type enum" do
        expect(dependencies.first.type).to eq("other")
      end
    end

    [nil, 1].each do |value|
      context "with type set to #{value.inspect}" do
        let(:type) { value }

        it "rejects the malformed type" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, /type/)
        end
      end
    end
  end
end
