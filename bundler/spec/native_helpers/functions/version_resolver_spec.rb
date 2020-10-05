# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"

require "dependabot/dependency"
require_relative "../../../helpers/lib/functions/version_resolver"

RSpec.describe Functions::VersionResolver do
  let(:version_resolver) do
    described_class.new(
      dependency_name: dependency_name,
      dependency_requirements: [],
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      dir: fixture_directory,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:fixture_directory) do
    File.join(
      File.dirname(__FILE__), "..", "..", "fixtures", "ruby", "gemfiles"
    )
  end
  let(:gemfile_name) do
    File.join(fixture_directory, gemfile_fixture_name)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "business" }
  let(:current_version) { "1.3" }
  let(:requirements) do
    [{
      file: "Gemfile",
      requirement: requirement_string,
      groups: [],
      source: source
    }]
  end
  let(:source) { nil }
  let(:requirement_string) { ">= 0" }

  let(:gemfile_fixture_name) { "Gemfile" }
  let(:lockfile_fixture_name) { "Gemfile.lock" }

  let(:rubygems_url) { "https://index.rubygems.org/api/v1/" }
end
