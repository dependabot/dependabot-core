#!/usr/bin/env ruby
# frozen_string_literal: true
require "optparse"

$options = {
  dependency_name:nil
}

option_parse = OptionParser.new do |opts|
  opts.banner = "usage: ruby bin/demo.rb [OPTIONS] REPO"

  opts.on("--dep DEPENDENCY", "Dependency to update") do |value|
    $options[:dependency_name] = value
  end
end
option_parse.parse!

$dep_option
if $options[:dependency_name].nil? 
   $dep_option = ''
else
  $dep_option = "--dep #{$options[:dependency_name]}"
end


if ARGV.length < 1
  puts option_parse.help
  exit 1
end

$repo_name = ARGV[0]
cmd = "ruby bin/dry-run.rb #{$dep_option} --azure-token {azure_token_goes_here} npm_and_yarn #{$repo_name}"
system(cmd)
