# frozen_string_literal: true

require "native_spec_helper"

RSpec.describe Functions do
  # Verify v1 method signatures are exist, but raise as NYI
  {
    parsed_gemfile: [ :lockfile_name, :gemfile_name, :dir ],
    parsed_gemspec: [ :lockfile_name, :gemspec_name, :dir ],
    vendor_cache_dir: [ :dir ],
    update_lockfile: [ :dir, :gemfile_name, :lockfile_name, :using_bundler2, :credentials, :dependencies ],
    force_update: [ :dir, :dependency_name, :target_version, :gemfile_name, :lockfile_name, :using_bundler2,
                    :credentials, :update_multiple_dependencies ],
    dependency_source_type: [ :gemfile_name, :dependency_name, :dir, :credentials ],
    depencency_source_latest_git_version: [ :gemfile_name, :dependency_name, :dir, :credentials, :dependency_source_url,
                                            :dependency_source_branch  ],
    private_registry_versions: [:gemfile_name, :dependency_name, :dir, :credentials ],
    resolve_version: [:dependency_name, :dependency_requirements, :gemfile_name, :lockfile_name, :using_bundler2,
                      :dir, :credentials],
    jfrog_source: [:dir, :gemfile_name, :credentials, :using_bundler2],
    git_specs: [:dir, :gemfile_name, :credentials, :using_bundler2],
    set_bundler_flags_and_credentials: [:dir, :credentials, :using_bundler2],
    conflicting_dependencies: [:dir, :dependency_name, :target_version, :lockfile_name, :using_bundler2, :credentials]
  }.each do |function, kwargs|
    describe "::#{function}" do
      let(:args) do
        kwargs.inject({}) do |args, keyword|
          args.merge({ keyword => anything })
        end
      end

      it "raises a NYI" do
        expect { Functions.send(function, **args) }.to raise_error(Functions::NotImplementedError)
      end
    end
  end
end
