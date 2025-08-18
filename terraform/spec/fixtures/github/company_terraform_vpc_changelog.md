# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-01-15

### Added
- Initial stable release of the VPC module
- Support for creating VPC with configurable CIDR block
- Public and private subnet creation across multiple AZs
- Internet Gateway and NAT Gateway setup
- Route table configuration for public and private subnets
- Security group module for default VPC security groups
- Comprehensive documentation and examples

### Changed
- Upgraded minimum Terraform version requirement to 1.0
- Upgraded minimum AWS provider version to 4.0
- Improved variable validation and descriptions

### Fixed
- Fixed issue with route table associations
- Resolved NAT Gateway dependency issues

## [0.9.0] - 2024-01-10

### Added
- Beta release of VPC module
- Basic VPC creation functionality
- Public subnet support
- Internet Gateway setup
- Basic route table configuration

### Known Issues
- Private subnets not yet supported
- NAT Gateway functionality incomplete
- Limited documentation

## [0.8.0] - 2024-01-05

### Added
- Initial alpha release
- Basic VPC resource creation
- Minimal subnet support

### Known Issues
- Many features incomplete
- Not recommended for production use