# typed: strict
# frozen_string_literal: true

require "fileutils"
require "erb"
require "io/console"

# Ecosystem scaffolder class that generates boilerplate files for a new ecosystem
class EcosystemScaffolder
  extend T::Sig

  sig { params(name: String, overwrite_mode: String).void }
  def initialize(name, overwrite_mode = "ask")
    @ecosystem_name = T.let(name, String)
    @ecosystem_module = T.let(name.split("_").map(&:capitalize).join, String)
    @template_dir = T.let(File.expand_path("ecosystem_templates", __dir__), String)
    @initial_overwrite_mode = T.let(overwrite_mode, String)
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

  sig { returns(String) }
  attr_reader :template_dir

  sig { returns(String) }
  attr_reader :initial_overwrite_mode

  sig { returns(String) }
  def current_overwrite_mode
    @current_overwrite_mode ||= T.let(@initial_overwrite_mode, T.nilable(String))
  end

  sig { params(mode: String).void }
  def overwrite_mode(mode)
    @current_overwrite_mode = T.let(mode, T.nilable(String))
  end

  sig { void }
  def create_directory_structure
    puts "Creating directory structure..."

    directories = [
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/helpers",
      "#{ecosystem_name}/spec",
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
    create_file_from_template(
      "main_registration.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}.rb"
    )

    # Required class files
    create_file_from_template(
      "file_fetcher.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_fetcher.rb"
    )
    create_file_from_template(
      "file_parser.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_parser.rb"
    )
    create_file_from_template(
      "update_checker.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/update_checker.rb"
    )
    create_file_from_template(
      "file_updater.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/file_updater.rb"
    )

    # Optional class files (with deletion comments)
    create_file_from_template(
      "metadata_finder.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/metadata_finder.rb"
    )
    create_file_from_template(
      "version.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/version.rb"
    )
    create_file_from_template(
      "requirement.rb.erb",
      "#{ecosystem_name}/lib/dependabot/#{ecosystem_name}/requirement.rb"
    )
  end

  sig { void }
  def create_spec_files
    puts ""
    puts "Creating test files..."

    # Spec helper
    create_file_from_template(
      "spec_helper.rb.erb",
      "#{ecosystem_name}/spec/spec_helper.rb"
    )

    # Test files
    create_file_from_template(
      "file_fetcher_spec.rb.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_fetcher_spec.rb"
    )
    create_file_from_template(
      "file_parser_spec.rb.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_parser_spec.rb"
    )
    create_file_from_template(
      "update_checker_spec.rb.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/update_checker_spec.rb"
    )
    create_file_from_template(
      "file_updater_spec.rb.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/file_updater_spec.rb"
    )
    create_file_from_template(
      "metadata_finder_spec.rb.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/metadata_finder_spec.rb"
    )

    # Fixtures README
    create_file_from_template(
      "fixtures_README.md.erb",
      "#{ecosystem_name}/spec/dependabot/#{ecosystem_name}/fixtures/README.md"
    )
  end

  sig { void }
  def create_supporting_files
    puts ""
    puts "Creating supporting files..."

    create_file_from_template("README.md.erb", "#{ecosystem_name}/README.md")
    create_file_from_template("Dockerfile.erb", "#{ecosystem_name}/Dockerfile")
    create_file_from_template("gemspec.erb", "#{ecosystem_name}/dependabot-#{ecosystem_name}.gemspec")
    create_file_from_template("gitignore.erb", "#{ecosystem_name}/.gitignore")
    create_file_from_template("rubocop.yml.erb", "#{ecosystem_name}/.rubocop.yml")
    create_file_from_template("bundle_config.erb", "#{ecosystem_name}/.bundle/config")
    create_file_from_template("build_script.erb", "#{ecosystem_name}/script/build")
    create_file_from_template("ci-test.erb", "#{ecosystem_name}/script/ci-test")

    # Make scripts executable
    FileUtils.chmod(0o755, "#{ecosystem_name}/script/build")
    FileUtils.chmod(0o755, "#{ecosystem_name}/script/ci-test")
  end

  sig { params(template_name: String, output_path: String).void }
  def create_file_from_template(template_name, output_path)
    # Check if file exists and handle based on overwrite mode
    if File.exist?(output_path)
      case current_overwrite_mode
      when "skip"
        puts "  ⊘ Skipped #{output_path} (already exists)"
        return
      when "ask"
        print "  ? File #{output_path} exists. Overwrite? [y/N/a(ll)/s(kip all)]: "
        response = $stdin.gets.to_s.strip.downcase
        case response
        when "a", "all"
          overwrite_mode("force")
        when "s", "skip", "skip all"
          overwrite_mode("skip")
          puts "  ⊘ Skipped #{output_path}"
          return
        when "y", "yes"
          # Continue to create file
        else
          puts "  ⊘ Skipped #{output_path}"
          return
        end
      when "force"
        # Continue to create file
      end
    end

    template_path = File.join(template_dir, template_name)
    template_content = File.read(template_path)
    erb = ERB.new(template_content, trim_mode: "-")
    content = erb.result(binding)

    File.write(output_path, content)
    puts "  ✓ Created #{output_path}"
  end
end
