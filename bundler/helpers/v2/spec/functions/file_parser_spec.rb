# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"
require "json"

RSpec.describe Functions::FileParser do
  include_context "when in a temporary bundler directory"

  let(:dependency_source) do
    described_class.new(
      lockfile_name: "Gemfile.lock"
    )
  end

  describe "#parsed_gemfile" do
    subject(:parsed_gemfile) do
      in_tmp_folder do
        dependency_source.parsed_gemfile(gemfile_name: "Gemfile")
      end
    end

    let(:project_name) { "gemfile" }

    it "parses gemfile" do
      expected = [
        {
          "groups" => ["default"],
          "name" => "business",
          "requirement" => "~> 1.4.0",
          "source" => nil,
          "type" => "runtime"
        },
        {
          "groups" => ["default"],
          "name" => "statesman",
          "requirement" => "~> 1.2.0",
          "source" => nil,
          "type" => "runtime"
        }
      ]
      expect(JSON.parse(JSON.dump(parsed_gemfile))).to eq(expected)
    end

    context "with a git source" do
      let(:project_name) { "git_source" }

      it "parses gemfile" do
        expected = [
          {
            "groups" => ["default"],
            "name" => "business",
            "requirement" => "~> 1.6.0",
            "source" => {
              "branch" => nil,
              "ref" => "a1b78a9",
              "type" => "git",
              "url" => "git@github.com:dependabot-fixtures/business"
            },
            "type" => "runtime"
          },
          {
            "groups" => ["default"],
            "name" => "statesman",
            "requirement" => "~> 1.2.0",
            "source" => nil,
            "type" => "runtime"
          },
          {
            "groups" => ["default"],
            "name" => "prius",
            "requirement" => ">= 0",
            "source" => {
              "branch" => nil,
              "ref" => nil,
              "type" => "git",
              "url" => "https://github.com/dependabot-fixtures/prius"
            },
            "type" => "runtime"
          },
          {
            "groups" => ["default"],
            "name" => "que",
            "requirement" => ">= 0",
            "source" => {
              "branch" => nil,
              "ref" => "v0.11.6",
              "type" => "git",
              "url" => "git@github.com:dependabot-fixtures/que"
            },
            "type" => "runtime"
          },
          {
            "groups" => ["default"],
            "name" => "uk_phone_numbers",
            "requirement" => ">= 0",
            "source" => {
              "branch" => nil,
              "ref" => nil,
              "type" => "git",
              "url" => "https://github.com/dependabot-fixtures/uk_phone_numbers"
            },
            "type" => "runtime"
          }
        ]
        expect(JSON.parse(JSON.dump(parsed_gemfile))).to eq(expected)
      end
    end
  end

  describe "#parsed_gemspec" do
    subject(:parsed_gemspec) do
      in_tmp_folder do |_tmp_path|
        dependency_source.parsed_gemspec(gemspec_name: "example.gemspec")
      end
    end

    let(:project_name) { "gemfile_exact" }

    it "parses gemspec" do
      expected = [
        {
          "groups" => nil,
          "name" => "business",
          "requirement" => "= 1.0.0",
          "source" => nil,
          "type" => "runtime"
        },
        {
          "groups" => nil,
          "name" => "statesman",
          "requirement" => "= 1.0.0",
          "source" => nil,
          "type" => "runtime"
        }
      ]
      expect(JSON.parse(JSON.dump(parsed_gemspec))).to eq(expected)
    end
  end
end
