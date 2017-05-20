# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/php/composer"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Bump::UpdateCheckers::Php::Composer do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [composer_file, lockfile],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Bump::Dependency.new(
      name: "monolog/monolog",
      version: "1.0.1",
      package_manager: "composer"
    )
  end

  let(:composer_file) do
    Bump::DependencyFile.new(
      content: composer_file_content,
      name: "composer.json"
    )
  end
  let(:lockfile) do
    Bump::DependencyFile.new(
      content: lockfile_content,
      name: "composer.lock"
    )
  end
  let(:composer_file_content) do
    fixture("php", "composer_files", "exact_version")
  end
  let(:lockfile_content) { fixture("php", "lockfiles", "exact_version") }

  describe "#latest_version" do
    subject { checker.latest_version }

    pending { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Bump::Dependency.new(
          name: "symfony/console",
          version: "2.7.3",
          package_manager: "composer"
        )
      end

      let(:composer_file_content) do
        fixture("php", "composer_files", "version_conflict")
      end
      let(:lockfile_content) do
        fixture("php", "lockfiles", "version_conflict")
      end

      pending { is_expected.to be < Gem::Version.new("3.0.0") }
    end
  end
end
