# frozen_string_literal: true

require "native_spec_helper"
require "shared_contexts"

RSpec.describe Functions::ConflictingDependencyResolver do
  include_context "in a temporary bundler directory"

  let(:conflicting_dependency_resolver) do
    described_class.new(
      dependency_name: dependency_name,
      target_version: target_version,
      lockfile_name: "Gemfile.lock"
    )
  end

  let(:dependency_name) { "dummy-pkg-a" }
  let(:target_version) { "2.0.0" }

  let(:project_name) { "blocked_by_subdep" }

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

    context "for nested transitive dependencies" do
      let(:project_name) { "transitive_blocking" }
      let(:dependency_name) { "activesupport" }
      let(:target_version) { "6.0.0" }

      it "returns a list of dependencies that block the update" do
        expect(conflicting_dependencies).to match_array(
          [
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0)",
              "name" => "rails",
              "requirement" => "= 5.2.0",
              "version" => "5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via actionpack (5.2.0)",
              "name" => "actionpack",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via actionview (5.2.0)",
              "name" => "actionview",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via activejob (5.2.0)",
              "name" => "activejob",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via activemodel (5.2.0)",
              "name" => "activemodel",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via activerecord (5.2.0)",
              "name" => "activerecord",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            },
            {
              "explanation" => "rails (5.2.0) requires activesupport (= 5.2.0) via railties (5.2.0)",
              "name" => "railties",
              "version" => "5.2.0",
              "requirement" => "= 5.2.0"
            }
          ]
        )
      end
    end

    context "with multiple blocking dependencies" do
      let(:dependency_name) { "activesupport" }
      let(:current_version) { "5.0.0" }
      let(:target_version) { "6.0.0" }
      let(:project_name) { "multiple_blocking" }

      it "returns all of the blocking dependencies" do
        expect(conflicting_dependencies).to match_array(
          [
            {
              "explanation" => "actionmailer (5.0.0) requires activesupport (= 5.0.0) via actionpack (5.0.0)",
              "name" => "actionpack",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            },
            {
              "explanation" => "actionview (5.0.0) requires activesupport (= 5.0.0)",
              "name" => "actionview",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            },
            {
              "explanation" => "actionmailer (5.0.0) requires activesupport (= 5.0.0) via activejob (5.0.0)",
              "name" => "activejob",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            }
          ]
        )
      end
    end

    context "without any blocking dependencies" do
      let(:target_version) { "1.0.0" }

      it "returns an empty list" do
        expect(conflicting_dependencies).to eq([])
      end
    end
  end
end
