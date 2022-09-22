# frozen_string_literal: true

require "rspec/its"
require "webmock/rspec"
require "debug"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../monkey_patches", __dir__))

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

def project_dependency_files(project)
  project_path = File.expand_path(File.join("../../spec/fixtures/projects/bundler2", project))

  raise "Fixture does not exist for project: '#{project}'" unless Dir.exist?(project_path)

  Dir.chdir(project_path) do
    # NOTE: Include dotfiles (e.g. .npmrc)
    files = Dir.glob("**/*", File::FNM_DOTMATCH)
    files = files.select { |f| File.file?(f) }
    files.map do |filename|
      content = File.read(filename)
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
