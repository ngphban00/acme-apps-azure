terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "ngphban"

    workspaces {
      name = "acme-apps-azure-dev"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

module "order_portal" {
  source  = "app.terraform.io/ngphban/order-portal/azurerm"
  version = "~> 1.0"

  name            = "acme-order-portal"
  environment     = var.environment
  cost_center     = var.cost_center
  owner           = var.owner
  azure_region    = var.azure_region
  index_html_path  = "${path.module}/index.html"
  replication_type = "GRS"
  access_tier      = "Cool"
}
