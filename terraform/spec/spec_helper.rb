# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

module PackageManagerHelper
  def self.use_terraform_hcl2?
    ENV["SUITE_NAME"] == "terraform-hcl2"
  end

  def self.use_terraform_hcl1?
    !use_terraform_hcl2?
  end
end

RSpec.configure do |config|
  config.around do |example|
    if PackageManagerHelper.use_terraform_hcl2? && example.metadata[:hcl1_only]
      example.skip
    elsif PackageManagerHelper.use_terraform_hcl1? && example.metadata[:hcl2_only]
      example.skip
    else
      example.run
    end
  end
end

if ENV["COVERAGE"]
  # TODO: Bring branch coverage up
  SimpleCov.minimum_coverage line: 80, branch: 55
end
