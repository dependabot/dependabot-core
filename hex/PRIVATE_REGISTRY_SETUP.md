# Hex Private Registry Setup for Integration Tests

Some Hex integration specs test private package functionality using a Hex.pm organization. These tests skip gracefully when credentials are not available, so local development works without them.

## Local Testing

The `HEX_PM_ORGANIZATION_TOKEN` environment variable is required to run private registry tests. Contact repository maintainers if you need access.

## Running Tests Locally

**Option 1: Export before starting Docker** (recommended)
```bash
# Set the token (contact maintainers for access)
export HEX_PM_ORGANIZATION_TOKEN="<your-token>"

# Start Docker container (environment variable is passed through)
bin/docker-dev-shell hex

# Inside container:
cd hex && rspec spec
```

**Option 2: Export inside Docker container**
```bash
# Start Docker container first
bin/docker-dev-shell hex

# Inside container, export the token:
export HEX_PM_ORGANIZATION_TOKEN="<token>"
cd hex && rspec spec
```

**Without token**: Tests skip automatically (no failures).

## CI/CD

The GitHub Actions CI workflow is configured to pass `HEX_PM_ORGANIZATION_TOKEN` to test containers via [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). This allows integration tests to run against the real Hex.pm organization in CI.

## References

- [Hex credential helpers implementation](../common/lib/dependabot/credential_helpers.rb)
- [Hex.pm Organizations documentation](https://hex.pm/docs/organizations)
