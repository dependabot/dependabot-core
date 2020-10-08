# frozen_string_literal: true

require "excon"

module SharedNativeHelpers
  # Duplicated in lib/dependabot/bundler/file_updater/lockfile_updater.rb
  # TODO: Stop sanitizing the lockfile once we have bundler 2 installed
  LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m.freeze
end
