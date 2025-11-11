# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

# Register Julia version and requirement classes
require "dependabot/julia/version"
require "dependabot/julia/requirement"

module Dependabot
  module Julia
    extend T::Sig

    VERSION = "0.1.0"

    sig { returns(String) }
    def self.package_ecosystem
      "julia"
    end

    sig { returns(T.class_of(Dependabot::Julia::FileFetcher)) }
    def self.file_fetcher_class
      FileFetcher
    end

    sig { returns(T.class_of(Dependabot::Julia::FileParser)) }
    def self.file_parser_class
      FileParser
    end

    sig { returns(T.class_of(Dependabot::Julia::UpdateChecker)) }
    def self.update_checker_class
      UpdateChecker
    end

    sig { returns(T.class_of(Dependabot::Julia::FileUpdater)) }
    def self.file_updater_class
      FileUpdater
    end

    sig { returns(T.class_of(Dependabot::Julia::MetadataFinder)) }
    def self.metadata_finder_class
      MetadataFinder
    end

    sig { returns(T.class_of(Dependabot::Julia::Dependency)) }
    def self.dependency_class
      Dependabot::Julia::Dependency
    end

    sig { returns(T.class_of(Dependabot::Julia::PackageManager)) }
    def self.package_manager_class
      PackageManager
    end
  end
end

require "dependabot/julia/package_manager"
require "dependabot/julia/file_fetcher"
require "dependabot/julia/file_parser"
require "dependabot/julia/update_checker"
require "dependabot/julia/file_updater"
require "dependabot/julia/metadata_finder"
require "dependabot/julia/dependency"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("julia", name: "julia", colour: "a270ba")

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check("julia", ->(_) { true })
