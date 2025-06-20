# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

ENV["DEPENDABOT_NUGET_TEST_RUN"] = "true"
ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"

def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

def nuget_project_dependency_files(project, directory: "/")
  project_dependency_files(project, directory: directory)
end

def nuget_build_tmp_repo(project)
  build_tmp_repo(project, path: "projects")
end

require "#{common_dir}/spec/spec_helper.rb"
