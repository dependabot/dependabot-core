# typed: false
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

require "dependabot/azure_pipelines/package/azure_devops_http"

RSpec.configure do |config|
  # Retries back off for real between attempts; specs should not wait for them.
  config.before { allow(Dependabot::AzurePipelines::Package::AzureDevOpsHttp).to receive(:wait) }
end
