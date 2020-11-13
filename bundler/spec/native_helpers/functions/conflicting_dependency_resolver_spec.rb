# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::ConflictingDependencyResolver do
  include_context "in a temporary bundler directory"

  let(:conflicting_dependency_resolver) do
    described_class.new(
      dependency_name: dependency_name,
      target_version: target_version,
      lockfile_name: lockfile_name
    )
  end

  let(:dependency_name) { "dummy-pkg-a" }
  let(:target_version) { "2.0.0" }

  let(:gemfile_fixture_name) { "blocked_by_subdep" }
  let(:lockfile_fixture_name) { "blocked_by_subdep.lock" }

  describe "#conflicting_dependencies" do
    subject(:conflicting_dependencies) do
      in_tmp_folder { conflicting_dependency_resolver.conflicting_dependencies }
    end

    it "returns a list of dependencies that block the update" do
      expect(conflicting_dependencies).to eq(
        [{
          "explanation" => "dummy-pkg-b (1.0.0) requires dummy-pkg-a (< 2.0.0)",
          "name" => "dummy-pkg-b",
          "version" => "1.0.0",
          "requirement" => "< 2.0.0"
        }]
      )
    end

    context "without any blocking dependencies" do
      let(:target_version) { "1.0.0" }

      it "returns an empty list" do
        expect(conflicting_dependencies).to eq([])
      end
    end
  end
end
