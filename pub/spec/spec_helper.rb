# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

def runGit(args, dir)
  stdout, stderr, status = Open3.capture3(
    {
      "GIT_AUTHOR_NAME" => "Pub Test",
      "GIT_AUTHOR_EMAIL"=> "pub@dartlang.org",
      "GIT_COMMITTER_NAME"=> "Pub Test",
      "GIT_COMMITTER_EMAIL"=> "pub@dartlang.org",
      # To make stable commits ids we fix the date.
      "GIT_COMMITTER_DATE" => "1970-01-01T00:00:00.000",
      "GIT_AUTHOR_DATE" => "1970-01-01T00:00:00.000",
    },
    "git",
    *args,
    chdir: dir
  )
  if status != 0
    raise "git #{args.join(' ')} failed `#{stdout}` `#{stderr}`"
  end
  return stdout
end

shared_context :uses_temp_dir do
  around do |example|
    Dir.mktmpdir("rspec-") do |dir|
      @temp_dir = dir
      example.run
    end
  end

  attr_reader :temp_dir
end

require "#{common_dir}/spec/spec_helper.rb"
