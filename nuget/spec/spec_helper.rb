# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

ENV["DEPENDABOT_NUGET_TEST_RUN"] = "true"
ENV["DEPENDABOT_NUGET_CACHE_DISABLED"] = "true"

sig { returns(String) }
def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

sig { params(path: String).void }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

sig { params(project: String, directory: String).returns(T.untyped) }
def nuget_project_dependency_files(project, directory: "/")
  project_dependency_files(project, directory: directory)
end

sig { params(project: String).returns(T.untyped) }
def nuget_build_tmp_repo(project)
  build_tmp_repo(project, path: "projects")
end

require "#{common_dir}/spec/spec_helper.rb"
