# typed: false
# frozen_string_literal: true

require "rspec/its"
require "webmock/rspec"
require "webmock/http_lib_adapters/excon_adapter"
require "debug"

# Bundler 4's stricter $LOAD_PATH handling breaks RSpec's lazy autoload of
# built-in matchers (e.g. `satisfy`, `raise_error`, `contain_exactly`, `has`).
# Eagerly load all of them so tests don't hit LoadError mid-run.
Gem.loaded_specs["rspec-expectations"]&.then do |spec|
  Dir[File.join(spec.full_gem_path, "lib/rspec/matchers/built_in/*.rb")].each { |f| require f }
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$LOAD_PATH.unshift(File.expand_path("../monkey_patches", __dir__))
$LOAD_PATH.unshift(File.expand_path("../../spec_helpers", __dir__))

# Bundler monkey patches
require "definition_ruby_version_patch"
require "definition_bundler_version_patch"
require "git_source_patch"

require "functions"

require "gem_net_http_adapter"

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
