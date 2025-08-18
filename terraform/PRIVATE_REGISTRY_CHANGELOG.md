# Private Registry Changelog Support

This document describes the enhanced support for changelog and release information when using private Terraform registries with Dependabot.

## Overview

Dependabot now provides changelog and release information for Terraform modules hosted in private registries, similar to the functionality available for public registry modules. This enhancement helps developers understand what changes are included in module updates from private registries.

## How It Works

When Dependabot processes a Terraform module update from a private registry, it:

1. **Resolves the source repository** from the private registry's module metadata
2. **Fetches changelog information** from the source repository (CHANGELOG.md, HISTORY.md, etc.)
3. **Retrieves release notes** from GitHub/GitLab releases if available
4. **Includes this information** in the pull request description

## Configuration

### Private Registry Credentials

Configure your private registry credentials in your Dependabot configuration:

```yaml
# .github/dependabot.yml
version: 2
registries:
  private-terraform-registry:
    type: terraform-registry
    url: https://private-registry.example.com
    token: ${{ secrets.PRIVATE_REGISTRY_TOKEN }}

updates:
  - package-ecosystem: terraform
    directory: "/"
    schedule:
      interval: weekly
    registries:
      - private-terraform-registry
```

### Source Repository Credentials

If your private registry modules are hosted in private Git repositories, you'll also need to configure Git source credentials:

```yaml
# .github/dependabot.yml
version: 2
registries:
  private-terraform-registry:
    type: terraform-registry
    url: https://private-registry.example.com
    token: ${{ secrets.PRIVATE_REGISTRY_TOKEN }}
  
  private-github:
    type: git
    url: https://github.com
    username: x-access-token
    password: ${{ secrets.GITHUB_TOKEN }}

updates:
  - package-ecosystem: terraform
    directory: "/"
    schedule:
      interval: weekly
    registries:
      - private-terraform-registry
      - private-github
```

## Supported Source Repositories

The private registry changelog feature supports modules hosted on:

- **GitHub** (github.com and GitHub Enterprise)
- **GitLab** (gitlab.com and self-hosted GitLab)
- **Bitbucket** (bitbucket.org)
- **Azure DevOps** (dev.azure.com)

## Example Module Configuration

### Terraform Configuration

```hcl
# main.tf
module "vpc" {
  source = "company/vpc/aws"
  version = "1.2.0"  # Dependabot will update this
  
  cidr_block = "10.0.0.0/16"
  region     = "us-west-2"
}
```

### Private Registry Module Metadata

Your private registry should provide module metadata that includes the source repository URL:

```json
{
  "id": "company/vpc/aws/1.2.0",
  "source": "https://github.com/company/terraform-vpc",
  "description": "Company VPC module for AWS",
  "published_at": "2024-01-15T10:30:00Z"
}
```

### Source Repository Structure

Ensure your source repository includes changelog information:

```
terraform-vpc/
├── CHANGELOG.md          # Primary changelog file
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
└── examples/
    └── basic/
        └── main.tf
```

### Example CHANGELOG.md

```markdown
# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2024-01-15

### Added
- Support for multiple availability zones
- Enhanced security group configuration
- IPv6 support for subnets

### Changed
- Improved variable validation
- Updated AWS provider requirements to >= 4.0

### Fixed
- Fixed issue with route table associations
- Resolved NAT Gateway dependency issues

## [1.1.0] - 2024-01-10

### Added
- Basic VPC functionality
- Public and private subnet support
```

## Troubleshooting

### Common Issues

#### 1. No Changelog Information in PR

**Symptoms:**
- Dependabot creates PRs for private registry modules but doesn't include changelog information
- PR descriptions only show basic version update information

**Possible Causes:**
- Private registry doesn't provide source repository information
- Source repository is not accessible with current credentials
- Changelog files are not present in the source repository

**Solutions:**
1. Verify your private registry returns source repository URLs in module metadata
2. Ensure Git source credentials are configured for the source repository host
3. Add a CHANGELOG.md or similar file to your module's source repository

#### 2. Authentication Failures

**Symptoms:**
- Dependabot fails to update private registry modules
- Error messages about authentication failures

**Possible Causes:**
- Missing or incorrect private registry credentials
- Expired authentication tokens
- Insufficient permissions for the configured credentials

**Solutions:**
1. Verify your private registry token is correct and not expired
2. Ensure the token has appropriate permissions to read module metadata
3. Check that the registry URL is correct and accessible

#### 3. Source Repository Access Issues

**Symptoms:**
- Dependabot updates the module version but doesn't include changelog information
- Logs show source repository access failures

**Possible Causes:**
- Missing Git source credentials for the repository host
- Private repository requires different authentication
- Repository has been moved or deleted

**Solutions:**
1. Configure Git source credentials for the repository host (GitHub, GitLab, etc.)
2. Verify the source repository URL is correct and accessible
3. Ensure the Git credentials have read access to the repository

### Debugging

#### Enable Debug Logging

The private registry changelog feature includes structured logging to help with debugging. Look for log entries with:

- `Private registry operation:` - Normal operations
- `Private registry error:` - Error conditions

#### Common Log Messages

```
Private registry operation: source_resolution for private-registry.example.com
Private registry operation: metadata_finder_source_resolved for private-registry.example.com
Private registry error: PrivateSourceAuthenticationFailure for private-registry.example.com
```

#### Verify Registry Configuration

Test your private registry configuration manually:

```bash
# Test registry service discovery
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://private-registry.example.com/.well-known/terraform.json

# Test module metadata
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://private-registry.example.com/v1/modules/company/vpc/aws/1.2.0/download
```

#### Verify Source Repository Access

Test source repository access with your Git credentials:

```bash
# Test GitHub API access
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/company/terraform-vpc/contents

# Test GitLab API access  
curl -H "Authorization: Bearer YOUR_GITLAB_TOKEN" \
  https://gitlab.com/api/v4/projects/company%2Fterraform-vpc/repository/tree
```

## Best Practices

### Module Development

1. **Include Changelog Files**: Always include a CHANGELOG.md file in your module repositories
2. **Use Semantic Versioning**: Follow semantic versioning for your module releases
3. **Create GitHub/GitLab Releases**: Use releases with detailed release notes
4. **Document Breaking Changes**: Clearly document any breaking changes in your changelog

### Registry Configuration

1. **Provide Source URLs**: Ensure your private registry returns accurate source repository URLs
2. **Use Consistent Naming**: Use consistent module naming across registry and source repository
3. **Maintain Metadata**: Keep module metadata up-to-date with accurate descriptions and source URLs

### Credential Management

1. **Use Scoped Tokens**: Use tokens with minimal required permissions
2. **Rotate Credentials**: Regularly rotate authentication tokens
3. **Secure Storage**: Store credentials securely using GitHub Secrets or similar
4. **Monitor Access**: Monitor credential usage and access patterns

## Limitations

- **File Size Limits**: Changelog files larger than 1MB are skipped to prevent memory issues
- **Rate Limiting**: Subject to API rate limits of the source repository hosting service
- **Network Dependencies**: Requires network access to both private registry and source repository
- **Supported Formats**: Currently supports Markdown changelog files and GitHub/GitLab releases

## Support

If you encounter issues with private registry changelog support:

1. Check the troubleshooting section above
2. Review Dependabot logs for error messages
3. Verify your configuration matches the examples provided
4. Ensure your private registry and source repositories are properly configured

For additional support, please refer to the main Dependabot documentation or contact your system administrator.