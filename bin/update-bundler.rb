#!/usr/bin/env ruby
# frozen_string_literal: true

# This script bumps the bundler version used, since we reference it in a few
# different places.

require "excon"
require "json"

LATEST_VERSION = JSON.parse(Excon.get("https://rubygems.org/api/v1/gems/bundler.json").body)["version"]
CURRENT_VERSION = File.read("Dockerfile").match(/BUNDLER_V2_VERSION=(2.\d+\.\d+)/)[1]

def update_file(filename)
  File.open(filename, "r+") do |f|
    contents = f.read
    f.rewind
    f.write(contents.gsub(CURRENT_VERSION, LATEST_VERSION))
  end
end

update_file("Dockerfile")
update_file("bundler/helpers/v2/build")
update_file("bundler/lib/dependabot/bundler/helpers.rb")
update_file("bundler/spec/dependabot/bundler/helper_spec.rb")
update_file("bundler/script/ci-test")
update_file("bundler/spec/spec_helper.rb")
