# typed: strict
# frozen_string_literal: true

require "tmpdir"

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

# The updater image ships a vcpkg checkout at /opt/vcpkg, so any spec that builds a
# Package::VersionsDatabase without stubbing it would shell out to git and hit the network there
# while silently passing on a machine that has no checkout. Pointing VCPKG_ROOT somewhere that
# cannot exist makes the database report itself unavailable, so specs behave the same either way.
# Specs that exercise the versions database stub it explicitly.
ENV["VCPKG_ROOT"] = File.join(Dir.tmpdir, "dependabot-vcpkg-absent-registry")
