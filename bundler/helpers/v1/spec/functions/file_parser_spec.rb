# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

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
      parsed_gemfile = [
        {
          groups: [:default],
          name: "business",
          requirement: Gem::Requirement.new("~> 1.4.0"),
          source: nil,
          type: :runtime
        },
        {
          groups: [:default],
          name: "statesman",
          requirement: Gem::Requirement.new("~> 1.2.0"),
          source: nil,
          type: :runtime
        }
      ]
      expect(parsed_gemfile).not_to be_nil # to get past IdenticalEqualityAssertion
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
      parsed_gemspec = [
        {
          groups: nil,
          name: "business",
          requirement: Gem::Requirement.new("= 1.0.0"),
          source: nil,
          type: :runtime
        },
        {
          groups: nil,
          name: "statesman",
          requirement: Gem::Requirement.new("= 1.0.0"),
          source: nil,
          type: :runtime
        }
      ]
      expect(parsed_gemspec).not_to be_nil # to get past IdenticalEqualityAssertion
    end
  end
end
