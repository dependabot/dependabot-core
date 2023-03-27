# frozen_string_literal: true

require "bundler/source"

module Bundler
  class Source
    class Git
      class GitProxy
        private

        # Bundler allows ssh authentication when talking to GitHub but there's
        # no way for Dependabot to do so (it doesn't have any ssh keys).
        # Instead, we convert all `git@github.com:` URLs to use HTTPS.
        def configured_uri
          configured_uri_for(uri)
        end

        def configured_uri_for(uri)
          uri = uri.gsub(%r{git@(.*?):/?}, 'https://\1/')
          if /https?:/.match?(uri)
            remote = Bundler::URI(uri)
            config_auth = Bundler.settings[remote.to_s] || Bundler.settings[remote.host]
            remote.userinfo ||= config_auth
            remote.to_s
          elsif File.exist?(uri)
            "file://#{uri}"
          else
            uri
          end
        end
      end
    end
  end
end

module Bundler
  class Source
    class Git < Path
      private

      def serialize_gemspecs_in(destination)
        original_load_paths = $LOAD_PATH.dup
        reduced_load_paths = original_load_paths.
                             reject { |p| p.include?("/gems/") }

        $LOAD_PATH.shift until $LOAD_PATH.empty?
        reduced_load_paths.each { |p| $LOAD_PATH << p }

        destination = destination.expand_path(Bundler.root) if destination.relative?
        Dir["#{destination}/#{@glob}"].each do |spec_path|
          # Evaluate gemspecs and cache the result. Gemspecs
          # in git might require git or other dependencies.
          # The gemspecs we cache should already be evaluated.
          spec = Bundler.load_gemspec(spec_path)
          next unless spec

          Bundler.rubygems.set_installed_by_version(spec)
          Bundler.rubygems.validate(spec)
          File.binwrite(spec_path, spec.to_ruby)
        end
        $LOAD_PATH.shift until $LOAD_PATH.empty?
        original_load_paths.each { |p| $LOAD_PATH << p }
      end
    end
  end
end
