# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::ParentDependencyResolver do
  include_context "in a temporary bundler directory"

  let(:parent_dependency_resolver) do
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

  describe "#blocking_parent_dependencies" do
    subject(:blocking_parent_dependencies) do
      in_tmp_folder { parent_dependency_resolver.blocking_parent_dependencies }
    end

    it "returns a list of dependencies that block the update" do
      expect(blocking_parent_dependencies).to eq(
        [
          { name: "dummy-pkg-b", version: "1.0.0", requirement: "< 2.0.0" }
        ]
      )
    end

    context "without any blocking dependencies" do
      let(:target_version) { "1.0.0" }

      it "returns an empty list" do
        expect(blocking_parent_dependencies).to eq([])
      end
    end
  end
end
