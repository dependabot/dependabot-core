# frozen_string_literal: true

require "rspec/its"
require "webmock/rspec"
require "byebug"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
# TODO: Fork `v1/monkey_patches` into `v2/monkey_patches` ?
$LOAD_PATH.unshift(File.expand_path("../../v1/monkey_patches", __dir__))

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.raise_errors_for_deprecations!
end

# Duplicated in lib/dependabot/bundler/file_updater/lockfile_updater.rb
# TODO: Stop sanitizing the lockfile once we have bundler 2 installed
LOCKFILE_ENDING = /(?<ending>\s*(?:RUBY VERSION|BUNDLED WITH).*)/m.freeze

def project_dependency_files(project)
  project_path = File.expand_path(File.join("../../spec/fixtures/projects/bundler1", project))
  Dir.chdir(project_path) do
    # NOTE: Include dotfiles (e.g. .npmrc)
    files = Dir.glob("**/*", File::FNM_DOTMATCH)
    files = files.select { |f| File.file?(f) }
    files.map do |filename|
      content = File.read(filename)
      if filename == "Gemfile.lock"
        content = content.gsub(LOCKFILE_ENDING, "")
      end
      {
        name: filename,
        content: content
      }
    end
  end
end

def fixture(*name)
  File.read(File.join("../../spec/fixtures", File.join(*name)))
end
