# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::FileParser do
  include_context "in a temporary bundler directory"

  let(:dependency_source) do
    described_class.new(
      lockfile_name: "Gemfile.lock"
    )
  end

  let(:gemfile_fixture_name) { "Gemfile" }
  let(:lockfile_fixture_name) { "Gemfile.lock" }

  describe "#parsed_gemfile" do
    subject(:parsed_gemfile) do
      in_tmp_folder do
        dependency_source.parsed_gemfile(gemfile_name: "Gemfile")
      end
    end

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
      is_expected.to eq(parsed_gemfile)
    end
  end

  describe "#parsed_gemspec" do
    let!(:gemspec_fixture) do
      fixture("ruby", "gemspecs", "exact")
    end

    subject(:parsed_gemspec) do
      in_tmp_folder do |tmp_path|
        File.write(File.join(tmp_path, "test.gemspec"), gemspec_fixture)
        dependency_source.parsed_gemspec(gemspec_name: "test.gemspec")
      end
    end

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
      is_expected.to eq(parsed_gemspec)
    end
  end
end
