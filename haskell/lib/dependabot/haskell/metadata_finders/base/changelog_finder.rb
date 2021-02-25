# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/metadata_finders/base/changelog_finder"

module Dependabot
  module Haskell
    module MetadataFinders
      module Base
        class ChangelogFinder < Dependabot::MetadataFinders::Base::ChangelogFinder
          # Haskell's PVP versioning goes up to `major.major.minor.patch`,
          # rather than semver's `major.minor.patch`.
          def major_version_upgrade?
            return false unless dependency.version&.match?(/^\d/)
            return false unless dependency.previous_version&.match?(/^\d/)

            current = dependency.version.split(".")
            prev = dependency.previous_version.split(".")
            current[0].to_i > prev[0].to_i || (current[0].to_i == prev[0].to_i && current[1].to_i > prev[1].to_i)
          end
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "haskell",
  Dependabot::Haskell::MetadataFinders::Base::ChangelogFinder
)
