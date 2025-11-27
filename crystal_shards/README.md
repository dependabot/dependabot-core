# Dependabot Crystal Shards Support

Provides support for bumping Crystal Shards dependencies via Dependabot.

## Status

This is a minimal implementation of Crystal Shards support for Dependabot. It currently provides:

- FileFetcher: Identifies and fetches `shard.yml` and `shard.lock` files
- FileParser: Parses Crystal Shards manifests and extracts dependencies
- UpdateChecker: Basic update checking (minimal implementation)
- FileUpdater: Basic file updating (minimal implementation)

## Crystal Package Manager

Crystal uses Shards as its dependency manager. Dependencies are specified in `shard.yml` and resolved versions are tracked in `shard.lock`.

## Development

To run tests:
```bash
cd crystal_shards
bundle exec rspec
```
