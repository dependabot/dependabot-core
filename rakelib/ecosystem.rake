# typed: false
# frozen_string_literal: true

require "fileutils"
require "erb"
require_relative "support/helpers"

# Rake task for scaffolding new ecosystems
# sorbet: ignore
namespace :ecosystem do
  desc "Scaffold a new ecosystem (e.g., rake ecosystem:scaffold[bazel])"
  task :scaffold, [:name] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:scaffold[ecosystem_name]"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase

    # Validate ecosystem name format
    unless ecosystem_name.match?(/^[a-z][a-z0-9_]*$/)
      puts "Error: Ecosystem name must start with a letter and contain only " \
           "lowercase letters, numbers, and underscores."
      exit 1
    end

    # Check if ecosystem already exists
    if Dir.exist?(ecosystem_name)
      puts "Error: Directory '#{ecosystem_name}' already exists."
      exit 1
    end

    puts "Scaffolding new ecosystem: #{ecosystem_name}"
    puts ""

    scaffolder = EcosystemScaffolder.new(ecosystem_name)
    scaffolder.scaffold

    puts ""
    puts "✅ Ecosystem '#{ecosystem_name}' has been scaffolded successfully!"
    puts ""
    puts "Next steps:"
    puts "1. Implement the core classes in #{ecosystem_name}/lib/dependabot/#{ecosystem_name}/"
    puts "2. Add tests in #{ecosystem_name}/spec/dependabot/#{ecosystem_name}/"
    puts "3. Update supporting infrastructure (CI workflows, omnibus gem, etc.)"
    puts "4. See NEW_ECOSYSTEMS.md for complete implementation guide"
  end
end

# Ecosystem scaffolder class
# rubocop:disable Metrics/ClassLength
class EcosystemScaffolder
  extend T::Sig

  sig { params(name: String).void }
  def initialize(name)
    @ecosystem_name = T.let(name, String)
    @ecosystem_module = T.let(name.split("_").map(&:capitalize).join, String)
  end

  sig { void }
  def scaffold
    create_directory_structure
    create_lib_files
    create_spec_files
    create_supporting_files
  end

  private

  sig { returns(String) }
  attr_reader :ecosystem_name

  sig { returns(String) }
  attr_reader :ecosystem_module

  sig { void }
  def create_directory_structure
    puts "Creating directory structure..."

    directories = [
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/helpers",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/fixtures",
      "#{ecosystem_name}/.bundle",
      "#{ecosystem_name}/script"
    ]

    directories.each do |dir|
      FileUtils.mkdir_p(dir)
      puts "  ✓ Created #{dir}/"
    end
  end

  sig { void }
  def create_lib_files
    puts ""
    puts "Creating library files..."

    # Main registration file
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}.rb",
      main_registration_template
    )

    # Required class files
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_fetcher.rb",
      file_fetcher_template
    )
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_parser.rb",
      file_parser_template
    )
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/update_checker.rb",
      update_checker_template
    )
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_updater.rb",
      file_updater_template
    )

    # Optional class files (with deletion comments)
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/metadata_finder.rb",
      metadata_finder_template
    )
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/version.rb",
      version_template
    )
    create_file(
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/requirement.rb",
      requirement_template
    )
  end

  sig { void }
  def create_spec_files
    puts ""
    puts "Creating test files..."

    # Test files
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_fetcher_spec.rb",
      file_fetcher_spec_template
    )
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_parser_spec.rb",
      file_parser_spec_template
    )
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/update_checker_spec.rb",
      update_checker_spec_template
    )
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_updater_spec.rb",
      file_updater_spec_template
    )
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/metadata_finder_spec.rb",
      metadata_finder_spec_template
    )

    # Fixtures README
    create_file(
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/fixtures/README.md",
      fixtures_readme_template
    )
  end

  sig { void }
  def create_supporting_files
    puts ""
    puts "Creating supporting files..."

    create_file("#{ecosystem_name}/README.md", readme_template)
    create_file("#{ecosystem_name}/dependabot-#{ecosystem_name}.gemspec", gemspec_template)
    create_file("#{ecosystem_name}/.gitignore", gitignore_template)
    create_file("#{ecosystem_name}/.rubocop.yml", rubocop_template)
    create_file("#{ecosystem_name}/.bundle/config", bundle_config_template)
    create_file("#{ecosystem_name}/script/build", build_script_template)

    # Make build script executable
    FileUtils.chmod(0o755, "#{ecosystem_name}/script/build")
  end

  sig { params(path: String, content: String).void }
  def create_file(path, content)
    File.write(path, content)
    puts "  ✓ Created #{path}"
  end

  # Templates

  sig { returns(String) }
  def main_registration_template
    <<~RUBY
      # typed: strong
      # frozen_string_literal: true

      # These all need to be required so the various classes can be registered in a
      # lookup table of package manager names to concrete classes.
      require "dependabot/#{ecosystem_name}/file_fetcher"
      require "dependabot/#{ecosystem_name}/file_parser"
      require "dependabot/#{ecosystem_name}/update_checker"
      require "dependabot/#{ecosystem_name}/file_updater"
      require "dependabot/#{ecosystem_name}/metadata_finder"
      require "dependabot/#{ecosystem_name}/version"
      require "dependabot/#{ecosystem_name}/requirement"

      require "dependabot/pull_request_creator/labeler"
      Dependabot::PullRequestCreator::Labeler
        .register_label_details("#{ecosystem_name}", name: "#{ecosystem_name}", colour: "000000")

      require "dependabot/dependency"
      Dependabot::Dependency.register_production_check("#{ecosystem_name}", ->(_) { true })
    RUBY
  end

  sig { returns(String) }
  def file_fetcher_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      require "dependabot/file_fetchers"
      require "dependabot/file_fetchers/base"

      module Dependabot
        module #{ecosystem_module}
          class FileFetcher < Dependabot::FileFetchers::Base
            extend T::Sig

            sig { override.returns(String) }
            def self.required_files_message
              "Repo must contain a TODO manifest file."
            end

            sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
            def self.required_files_in?(filenames)
              # TODO: Implement logic to check if required files are present
              # Example: filenames.any? { |name| name == "manifest.json" }
              false
            end

            sig { override.returns(T::Array[DependencyFile]) }
            def fetch_files
              # Implement beta feature flag check
              unless allow_beta_ecosystems?
                raise Dependabot::DependencyFileNotFound.new(
                  nil,
                  "#{ecosystem_module} is currently in beta. Please contact Dependabot support to enable it."
                )
              end

              fetched_files = []

              # TODO: Implement file fetching logic
              # Example:
              # fetched_files << fetch_file_from_host("manifest.json")
      #{'        '}
              return fetched_files if fetched_files.any?

              raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message)
            end

            sig { override.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
            def ecosystem_versions
              # TODO: Return supported ecosystem versions
              # Example: { package_managers: { "#{ecosystem_name}" => "1.0.0" } }
              nil
            end
          end
        end
      end

      Dependabot::FileFetchers.register("#{ecosystem_name}", Dependabot::#{ecosystem_module}::FileFetcher)
    RUBY
  end

  sig { returns(String) }
  def file_parser_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      require "dependabot/dependency"
      require "dependabot/file_parsers"
      require "dependabot/file_parsers/base"

      module Dependabot
        module #{ecosystem_module}
          class FileParser < Dependabot::FileParsers::Base
            extend T::Sig

            sig { override.returns(T::Array[Dependabot::Dependency]) }
            def parse
              # TODO: Implement parsing logic to extract dependencies from manifest files
              # Return an array of Dependency objects
              []
            end

            private

            sig { override.void }
            def check_required_files
              # TODO: Verify that all required files are present
              # Example:
              # return if get_original_file("manifest.json")
              # raise "No manifest.json file found!"
            end
          end
        end
      end

      Dependabot::FileParsers.register("#{ecosystem_name}", Dependabot::#{ecosystem_module}::FileParser)
    RUBY
  end

  sig { returns(String) }
  def update_checker_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      require "dependabot/update_checkers"
      require "dependabot/update_checkers/base"

      module Dependabot
        module #{ecosystem_module}
          class UpdateChecker < Dependabot::UpdateCheckers::Base
            extend T::Sig

            sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
            def latest_version
              # TODO: Implement logic to find the latest version
              # This should check the package registry/repository for updates
              nil
            end

            sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
            def latest_resolvable_version
              # TODO: Implement logic to find the latest resolvable version
              # This might be the same as latest_version for simple ecosystems
              latest_version
            end

            sig { override.returns(T.nilable(String)) }
            def latest_resolvable_version_with_no_unlock
              # TODO: Implement logic for version resolution without unlocking
              dependency.version
            end

            sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
            def updated_requirements
              # TODO: Implement logic to update requirements
              # Return updated requirement hashes
              dependency.requirements
            end

            private

            sig { override.returns(T::Boolean) }
            def latest_version_resolvable_with_full_unlock?
              # TODO: Implement resolvability check
              false
            end

            sig { override.returns(T::Array[Dependabot::Dependency]) }
            def updated_dependencies_after_full_unlock
              # TODO: Return updated dependencies if full unlock is needed
              []
            end
          end
        end
      end

      Dependabot::UpdateCheckers.register("#{ecosystem_name}", Dependabot::#{ecosystem_module}::UpdateChecker)
    RUBY
  end

  sig { returns(String) }
  def file_updater_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      require "dependabot/file_updaters"
      require "dependabot/file_updaters/base"

      module Dependabot
        module #{ecosystem_module}
          class FileUpdater < Dependabot::FileUpdaters::Base
            extend T::Sig

            sig { override.returns(T::Array[Regexp]) }
            def self.updated_files_regex
              # TODO: Define regex patterns for files this updater can handle
              # Example: [/^manifest\\.json$/]
              []
            end

            sig { override.returns(T::Array[Dependabot::DependencyFile]) }
            def updated_dependency_files
              updated_files = []

              # TODO: Implement file update logic
              # For each file that needs updating:
              # 1. Get the original file content
              # 2. Update it with new dependency versions
              # 3. Add to updated_files array
              # Example:
              # manifest = dependency_files.find { |f| f.name == "manifest.json" }
              # updated_files << updated_file(file: manifest, content: new_content)

              updated_files
            end

            private

            sig { override.void }
            def check_required_files
              # TODO: Verify that all required files are present
              # Example:
              # return if get_original_file("manifest.json")
              # raise "No manifest.json file found!"
            end
          end
        end
      end

      Dependabot::FileUpdaters.register("#{ecosystem_name}", Dependabot::#{ecosystem_module}::FileUpdater)
    RUBY
  end

  sig { returns(String) }
  def metadata_finder_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      # NOTE: This file was scaffolded automatically but is OPTIONAL.
      # If you don't need custom metadata finding logic (changelogs, release notes, etc.),
      # you can safely delete this file and remove the require from lib/dependabot/#{ecosystem_name}.rb

      require "dependabot/metadata_finders"
      require "dependabot/metadata_finders/base"

      module Dependabot
        module #{ecosystem_module}
          class MetadataFinder < Dependabot::MetadataFinders::Base
            extend T::Sig

            private

            sig { override.returns(T.nilable(Dependabot::Source)) }
            def look_up_source
              # TODO: Implement custom source lookup logic if needed
              # Otherwise, delete this file and the require in the main registration file
              nil
            end
          end
        end
      end

      Dependabot::MetadataFinders.register("#{ecosystem_name}", Dependabot::#{ecosystem_module}::MetadataFinder)
    RUBY
  end

  sig { returns(String) }
  def version_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      # NOTE: This file was scaffolded automatically but is OPTIONAL.
      # If your ecosystem uses standard semantic versioning without special logic,
      # you can safely delete this file and remove the require from lib/dependabot/#{ecosystem_name}.rb

      require "dependabot/version"
      require "dependabot/utils"

      module Dependabot
        module #{ecosystem_module}
          class Version < Dependabot::Version
            extend T::Sig

            # TODO: Implement custom version comparison logic if needed
            # Example: Handle pre-release versions, build metadata, etc.
            # If standard semantic versioning is sufficient, delete this file
          end
        end
      end
    RUBY
  end

  sig { returns(String) }
  def requirement_template
    <<~RUBY
      # typed: strict
      # frozen_string_literal: true

      # NOTE: This file was scaffolded automatically but is OPTIONAL.
      # If your ecosystem uses standard Gem::Requirement logic,
      # you can safely delete this file and remove the require from lib/dependabot/#{ecosystem_name}.rb

      require "dependabot/requirement"
      require "dependabot/utils"

      module Dependabot
        module #{ecosystem_module}
          class Requirement < Dependabot::Requirement
            extend T::Sig

            # Add custom requirement parsing logic if needed
            # If standard Gem::Requirement is sufficient, delete this file

            # This abstract method must be implemented
            sig do
              override
              .params(requirement_string: T.nilable(String))
              .returns(T::Array[Dependabot::Requirement])
            end
            def self.requirements_array(requirement_string)
              # TODO: Implement requirement parsing logic
              # Example: Parse requirement_string and return array of requirements
              # For now, use the default implementation
              super
            end
          end
        end
      end
    RUBY
  end

  sig { returns(String) }
  def file_fetcher_spec_template
    <<~RUBY
      # typed: false
      # frozen_string_literal: true

      require "spec_helper"
      require "dependabot/#{ecosystem_name}/file_fetcher"
      require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

      RSpec.describe Dependabot::#{ecosystem_module}::FileFetcher do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end
        let(:url) { github_url + "repos/example/repo/contents/" }
        let(:github_url) { "https://api.github.com/" }
        let(:directory) { "/" }
        let(:source) do
          Dependabot::Source.new(
            provider: "github",
            repo: "example/repo",
            directory: directory
          )
        end
        let(:file_fetcher_instance) do
          described_class.new(
            source: source,
            credentials: credentials,
            repo_contents_path: nil
          )
        end

        before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

        # TODO: Add test cases
        # Example:
        # it "fetches manifest files" do
        #   # Test implementation
        # end
      end
    RUBY
  end

  sig { returns(String) }
  def file_parser_spec_template
    <<~RUBY
      # typed: false
      # frozen_string_literal: true

      require "spec_helper"
      require "dependabot/#{ecosystem_name}/file_parser"
      require_common_spec "file_parsers/shared_examples_for_file_parsers"

      RSpec.describe Dependabot::#{ecosystem_module}::FileParser do
        # TODO: Add test cases
        # Example:
        # it "parses dependencies correctly" do
        #   # Test implementation
        # end
      end
    RUBY
  end

  sig { returns(String) }
  def update_checker_spec_template
    <<~RUBY
      # typed: false
      # frozen_string_literal: true

      require "spec_helper"
      require "dependabot/#{ecosystem_name}/update_checker"
      require_common_spec "update_checkers/shared_examples_for_update_checkers"

      RSpec.describe Dependabot::#{ecosystem_module}::UpdateChecker do
        # TODO: Add test cases
        # Example:
        # it "finds latest version" do
        #   # Test implementation
        # end
      end
    RUBY
  end

  sig { returns(String) }
  def file_updater_spec_template
    <<~RUBY
      # typed: false
      # frozen_string_literal: true

      require "spec_helper"
      require "dependabot/#{ecosystem_name}/file_updater"
      require_common_spec "file_updaters/shared_examples_for_file_updaters"

      RSpec.describe Dependabot::#{ecosystem_module}::FileUpdater do
        # TODO: Add test cases
        # Example:
        # it "updates dependencies in manifest" do
        #   # Test implementation
        # end
      end
    RUBY
  end

  sig { returns(String) }
  def metadata_finder_spec_template
    <<~RUBY
      # typed: false
      # frozen_string_literal: true

      require "spec_helper"
      require "dependabot/#{ecosystem_name}/metadata_finder"
      require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

      RSpec.describe Dependabot::#{ecosystem_module}::MetadataFinder do
        # TODO: Add test cases
        # Example:
        # it "finds package source" do
        #   # Test implementation
        # end
      end
    RUBY
  end

  sig { returns(String) }
  def fixtures_readme_template
    <<~MARKDOWN
      # Test Fixtures

      This directory contains test fixtures for the #{ecosystem_name} ecosystem.

      Add sample manifest files, lockfiles, and other test data here.

      Example structure:
      ```
      fixtures/
      ├── manifest.json
      ├── lockfile.lock
      └── projects/
          ├── simple/
          └── complex/
      ```
    MARKDOWN
  end

  sig { returns(String) }
  def readme_template
    <<~MARKDOWN
      ## `dependabot-#{ecosystem_name}`

      #{ecosystem_module} support for [`dependabot-core`][core-repo].

      ### Running locally

      1. Start a development shell

        ```
        $ bin/docker-dev-shell #{ecosystem_name}
        ```

      2. Run tests
        ```
        [dependabot-core-dev] ~ $ cd #{ecosystem_name} && rspec
        ```

      [core-repo]: https://github.com/dependabot/dependabot-core

      ### Implementation Status

      This ecosystem is currently under development. See [NEW_ECOSYSTEMS.md](../NEW_ECOSYSTEMS.md) for implementation guidelines.

      #### Required Classes
      - [ ] FileFetcher
      - [ ] FileParser
      - [ ] UpdateChecker
      - [ ] FileUpdater

      #### Optional Classes
      - [ ] MetadataFinder
      - [ ] Version
      - [ ] Requirement

      #### Supporting Infrastructure
      - [ ] Comprehensive unit tests
      - [ ] CI/CD integration
      - [ ] Documentation
    MARKDOWN
  end

  sig { returns(String) }
  def gemspec_template
    <<~RUBY
      # frozen_string_literal: true

      Gem::Specification.new do |spec|
        common_gemspec =
          Bundler.load_gemspec_uncached("../common/dependabot-common.gemspec")

        spec.name         = "dependabot-#{ecosystem_name}"
        spec.summary      = "Provides Dependabot support for #{ecosystem_module}"
        spec.description  = "Dependabot-#{ecosystem_module} provides support for bumping #{ecosystem_module} dependencies via Dependabot. " \\
                            "If you want support for multiple package managers, you probably want the meta-gem " \\
                            "dependabot-omnibus."

        spec.author       = common_gemspec.author
        spec.email        = common_gemspec.email
        spec.homepage     = common_gemspec.homepage
        spec.license      = common_gemspec.license

        spec.metadata = {
          "bug_tracker_uri" => common_gemspec.metadata["bug_tracker_uri"],
          "changelog_uri" => common_gemspec.metadata["changelog_uri"]
        }

        spec.version = common_gemspec.version
        spec.required_ruby_version = common_gemspec.required_ruby_version
        spec.required_rubygems_version = common_gemspec.required_ruby_version

        spec.require_path = "lib"
        spec.files        = Dir["lib/**/*"]

        spec.add_dependency "dependabot-common", Dependabot::VERSION

        common_gemspec.development_dependencies.each do |dep|
          spec.add_development_dependency dep.name, *dep.requirement.as_list
        end
      end
    RUBY
  end

  sig { returns(String) }
  def gitignore_template
    <<~GITIGNORE
      .DS_Store
      *.gem
      .bundle
      vendor
    GITIGNORE
  end

  sig { returns(String) }
  def rubocop_template
    <<~YAML
      inherit_from: ../.rubocop.yml
    YAML
  end

  sig { returns(String) }
  def bundle_config_template
    <<~YAML
      ---
      BUNDLE_PATH: "../vendor/bundle"
      BUNDLE_DISABLE_SHARED_GEMS: "true"
    YAML
  end

  sig { returns(String) }
  def build_script_template
    <<~BASH
      #!/bin/bash

      set -e

      # Script for building native helpers (if needed)
      # TODO: Implement build logic for native helpers
      echo "No native helpers to build for #{ecosystem_name}"
    BASH
  end
end
# rubocop:enable Metrics/ClassLength
