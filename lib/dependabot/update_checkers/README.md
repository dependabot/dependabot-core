# Update checkers

Update checkers check whether a given dependency is up-to-date. If it isn't,
they augment it with details of the version to update to.

There is a `Dependabot::UpdateCheckers` class for each language Dependabot
supports.

## Public API

Each `Dependabot::UpdateCheckers` class implements the following methods:

| Method                       | Description                                                                                   |
|------------------------------|-----------------------------------------------------------------------------------------------|
| `#up_to_date?`               | Returns a boolean for whether the dependency this instance was created with is currently at the latest version. |
| `#can_update?`               | Returns a boolean for whether the dependency this instance was created with needs updating. This will be true if the dependency and/or its requirements can be updated to support a newer version whilst keeping the dependency files it came from resolvable. |
| `#updated_dependencies`      | Returns an array of updated `Dependabot::Dependency` instance with updated `version` and `requirements` attributes. The previous valuse are stored on the instance as `previous_version` and `previous_requirements`. |
| `#latest_version`            | See the "Writing an update checker" section. |
| `#latest_resolvable_version` | See the "Writing an update checker" section. |
| `#updated_requirements`      | See the "Writing an update checker" section. |

An integration might look as follows:

```ruby
require 'dependabot/update_checkers'

dependency = dependencies.first

update_checker_class = Dependabot::UpdateCheckers::Ruby::Bundler
update_checker = update_checker_class.new(
  dependency: dependency,
  dependency_files: files,
  credentials: [{
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => "token"
  }]
)

puts "Update needed for #{dependency.name}? "\
     "#{update_checker.can_update?(requirements_to_update: :own)}"
```

## Writing an update checker for a new language

All new update checkers should inherit from `Dependabot::UpdateCheckers::Base` and
implement the following methods:

| Method                       | Description                                                                                   |
|------------------------------|-----------------------------------------------------------------------------------------------|
| `#latest_version`            | The latest version of the dependency, ignoring resolvability. This is used to short-circuit update checking when the dependency is already at the latest version (since checking resolvability is typically slow). |
| `#latest_resolvable_version` | The latest version of the dependency that will still allow the full dependency set to resolve. |
| `#latest_resolvable_version_with_no_unlock` | The latest version of the dependency that satisfies the dependency's current version constraints and will still allow the full dependency set to resolve. |
| `#updated_requirements`      | An updated set of requirements for the dependency that should replace the existing requirements in the manifest file. Use by the file updater class when updating the manifest file. |
| `#latest_version_resolvable_with_full_unlock?` | A boolean for whether the latest version can be resolved if all other dependencies are unlocked in the manifest file. Can be set to always return `false` if multi-dependency updates aren't yet supported. |
| `#updated_dependencies_after_full_unlock` | And updated set of dependencies after a full unlock and update has taken place. Not required if `latest_version_resolvable_with_full_unlock?` always returns false. |


To ensure the above are implemented, you should include
`it_behaves_like "a dependency update checker"` in your specs for the new update
checker.

Writing update checkers generally gets tricky when resolvability has to
be taken into account. It is almost always easiest to do so in the language your
update checker relates to, so you may wish to shell out to that language. See
`UpdateCheckers::Php::Composer` for an example of how to do so.
