# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

$installed_versions = {}
$current_python_version = nil

def python_version_installed(version)
  $current_python_version = version
end

RSpec.configure do |config|
  config.before(:each) { $current_python_version = nil }
  config.after(:each) do |spec|
    next unless $current_python_version

    $installed_versions[spec.metadata[:full_description]] = $current_python_version
  end

  config.after(:suite) do
    $installed_versions.each do |example, version|
      puts "\n\n#{example} installed #{version}"
    end

    puts "Used python versions: \n#{$installed_versions.values.uniq.sort.join("\n")}"
  end
end
