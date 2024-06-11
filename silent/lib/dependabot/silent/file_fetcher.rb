# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "sorbet-runtime"

module SilentPackageManager
  class FileFetcher < Dependabot::FileFetchers::Base
    extend T::Sig

    sig { override.returns(T::Array[Dependabot::DependencyFile]) }
    def fetch_files
      [manifest].compact
    end

    private

    sig { returns(T.nilable(Dependabot::DependencyFile)) }
    def manifest
      fetch_file_if_present("manifest.json")
    end
  end
end

Dependabot::FileFetchers
  .register("silent", SilentPackageManager::FileFetcher)
