# File updatesr

File updaters update a dependency file to use the latest version of a given
dependency. They rely on information provided to them by update checkers.

There is a `Dependabot::FileUpdaters` class for each language Dependabot
supports.

## Public API

Each `Dependabot::FileUpdaters` class implements the following methods:

| Method                       | Description                                                                                   |
|------------------------------|-----------------------------------------------------------------------------------------------|
| `.updated_files_regex`       | An array of regular expressions matching the names of the files this class updates. Intended to be used by integrators when checking whether a commit may cause merge-conflicts with a dependency update pull request. |
| `#updated_dependency_files`  | Returns an array of updated `Dependabot::DependencyFile` instances, with their content updated to include the updated dependency. |

An integration might look as follows:

```ruby
require 'dependabot/file_updaters'

dependency = update_checker.updated_dependency

file_updater_class = Dependabot::FileUpdaters::Ruby::Bundler
file_updater = file_updater_class.new(
  dependency: dependency,
  dependency_files: files,
  github_access_token: "token"
)

file_updater.updated_dependency_files.each do |file|
  puts "Updated #{file.name} with new content:\n\n#{file.content}"
end
```

## Writing a file updater for a new language

All new file updaters should inherit from `Dependabot::FileUpdaters::Base` and
implement the following methods:

| Method                      | Description             |
|-----------------------------|-------------------------|
| `.updated_files_regex`      | See Public API section. |
| `#updated_dependency_files` | See Public API section. |

To ensure the above are implemented, you should include
`it_behaves_like "a dependency file updater"` in your specs for the new file
updater.

