# File fetchers

File fetchers are used to fetch the relevant dependency files for a project
(e.g., the `Gemfile` and `Gemfile.lock`). They are also responsible for checking
whether a repo has an admissable set of requirement files.

There is a `Dependabot::FileFetchers` class for each language Dependabot
supports.

## Public API

Each `Dependabot::FileFetchers` class implements the following methods:

| Method                           | Description                                                                                   |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `.required_files_in?`            | Checks an array of filenames (string) and returns a boolean describing whether the language-specific dependency files required for an update run are present. |
| `.required_files_message`        | Returns a static error message which can be displayed to a user if `required_files_in?` returns false. |
| `#files`                         | Fetches the language-specific dependency files for the repo this instance was created with. Returns an array of `Dependabot::DependencyFile` instances. |
| `#commit`                        | Returns the commit SHA-1 hash at the time the dependency files were fetched. If called before `files`, the returned value will be used in subsequent calls to `files`. |


An integration might look as follows:

```ruby
require 'octokit'
require 'dependabot/file_fetchers'

target_repo_name = 'dependabot/dependabot-core'

client = Octokit::Client.new
fetcher_class = Dependabot::FileFetchers::Ruby::Bundler
filenames = client.contents(target_repo_name).map(&:name)

unless fetcher_class.required_files_in?(filenames)
  raise fetcher_class.required_files_message
end

fetcher = fetcher_class.new(repo: target_repo_name, github_client: client)

puts "Fetched #{fetcher.files.map(&:name)}, at commit SHA-1 '#{fetcher.commit}'"
```

## Writing a file fetcher for a new language

All new file fetchers should inherit from `Dependabot::FileFetchers::Base` and
implement the following methods:

| Method                           | Description                                                                                   |
|----------------------------------|-----------------------------------------------------------------------------------------------|
| `.required_files_in?`            | See Public API section. |
| `.required_files_message`        | See Public API section. |
| `#fetch_files`                   | Private method to fetch the required files from GitHub. For each required file, you can use the `fetch_file_from_host(filename)` method from `Dependabot::FileFetchers::Base` to do the fetching. |

To ensure the above are implemented, you should include
`it_behaves_like "a dependency file fetcher"` in your specs for the new file
fetcher.

File fetchers tend to get complicated when the file requirements for an update
to run are non-trivial - for example, for Ruby we could accept
[`Gemfile`, `Gemfile.lock`] or [`Gemfile`, `example.gemspec`],
but not just [`Gemfile.lock`]. When adding a new lanugage, it's normally easiest
to pick a single case and implement it for all the update steps (parsing, update
checking, etc.). You can then return and add other cases later.
