# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::ForceUpdater do
  include_context "in a temporary bundler directory"
  include_context "stub rubygems compact index"

  let(:force_updater) do
    described_class.new(
      dependency_name: dependency_name,
      target_version: target_version,
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      update_multiple_dependencies: update_multiple_dependencies
    )
  end
  let(:gemfile_name) { "Gemfile" }
  let(:lockfile_name) { "Gemfile.lock" }
  let(:update_multiple_dependencies) { true }

  describe "#run" do
    subject(:force_update) do
      in_tmp_folder { force_updater.run }
    end

    context "with a version conflict" do
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-support" }
      let(:project_name) { "version_conflict" }

      it "updates the conflicting dependencies" do
        updated_deps, _specs = force_update
        expect(updated_deps).to eq([{ name: "rspec-support" }, { name: "rspec-mocks" }])
      end

      context "when updating a single dependency" do
        let(:update_multiple_dependencies) { false }

        it { expect { force_update }.to raise_error(Bundler::SolveFailure) }
      end
    end

    context "with a version conflict in gems rb" do
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-support" }
      let(:project_name) { "version_conflict_gems_rb" }
      let(:gemfile_name) { "gems.rb" }
      let(:lockfile_name) { "gems.locked" }

      it "updates the conflicting dependencies" do
        updated_deps, _specs = force_update
        expect(updated_deps).to eq([{ name: "rspec-support" }, { name: "rspec-mocks" }])
      end
    end
  end
end
