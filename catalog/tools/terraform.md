# Terraform MCP Tools

## Overview
Infrastructure-as-code provider and module lookup for Terraform/OpenTofu.

## Capabilities
- Provider documentation lookup
- Module discovery and documentation
- Resource and data source reference
- Provider version information

## Tool Prefix
`terraform_*` — 9 tools available

## Key Tools
| Tool | Description |
|------|-------------|
| `terraform_search_providers` | Search Terraform providers |
| `terraform_get_provider_docs` | Get provider documentation |
| `terraform_search_modules` | Search Terraform modules |
| `terraform_get_module_docs` | Get module documentation |
| `terraform_get_resource_docs` | Get resource type documentation |
| `terraform_list_resources` | List resources in a provider |

## Configuration
Transport: In-cluster MCP server.

## When to Use
- Writing Terraform/OpenTofu infrastructure code
- Looking up provider resource schemas
- Finding community modules
- Referencing provider documentation

## Tags
infrastructure-as-code, terraform, iac, cloud-infrastructure, providers, modules
