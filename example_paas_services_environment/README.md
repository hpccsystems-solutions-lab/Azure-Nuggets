# An Example Azure PaaS Services Environment

["Designing A PaaS Services Environment"](../designing_a_paas_services_environment/README.md) introduced us to the foundation that is required to create an Azure application environment. In this article we will deploy an application that uses multiple Azure services (App Service, Application Gateway, Azure MySQL Service, ...) to demonstrate an optimized environment that is secure and organized for expansion. 

For simplicity, we will name this application **Tombolo**.

The code repository for the project can be found [here](https://github.com/hpccsystems-solutions-lab/Azure-Terraform-Examples/tree/main/terraform-tombolo).


## STEP 0: Initialze main.tf 

```json
module "subscription" {
  source = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = var.subscription_id
}

module "naming" {
  source  = "github.com/LexisNexis-RBA/terraform-azurerm-naming"
  #version = "1.0.90"
}

module "metadata"{
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata?ref=v1.5.2"  
  #version = "1.5.2"
  naming_rules = module.naming.yaml
  
  market              = var.names.market
  location            = var.names.location 
  environment         = var.names.environment 
  project             = var.names.project
  business_unit       = var.names.business_unit
  product_group       = var.names.product_group
  product_name        = var.names.product_name 
  subscription_id     = module.subscription.output.subscription_id
  subscription_type   = var.names.subscription_type
  resource_group_type = var.names.resource_group_type
}
```

## STEP 1: Create a Resource Group

A Resource Group is a logical container that will hold all the resources that we create for the application. 

```json
module "resource-group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group"
  
  names    = module.metadata.names
  location = module.metadata.location
  tags     = module.metadata.tags
}
```

**TIP**: It is important to select the correct Azure Region where all the resources will be created. That said, when induvidual resources are created, you have the option of selection the region. While using the Portal we have to make sure both regions are the same as a best practice. If you write infrastructure as code (Bicep, Terraform etc.), all resources in the resource group will simply refer to the region of the resource group.    
 
## STEP 2: Virtual Network

For starters, let us create a Virtual Network that is used to secure the resources. In our example, we will use the following parameters:



```json
module "virtual_network" {
  source = "github.com/Azure-Terraform/terraform-azurerm-virtual-network"

  resource_group_name   = module.resource-group.name
  location              = module.resource-group.location
  names                 = module.metadata.names
  tags                  = module.metadata.tags

  address_space         = ["10.1.0.0/24"]
  
  enforce_subnet_names  = false
  
  subnets = {
    app-gateway = {
      cidrs = ["10.1.0.0/27"]
      create_network_security_group = false
    }

    app-ui = {
      cidrs = ["10.1.0.32/27"]
      enforce_private_link_endpoint_network_policies  = true
      enforce_private_link_service_network_policies   = true
      create_network_security_group = false
    }
    app-api = {
      cidrs = ["10.1.0.64/27"]
      delegations = {
        "delegation" = {
          name    = "Microsoft.Web/serverFarms"
          actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
        }
      }   
    }
    mysql-db = {
      cidrs = ["10.1.0.96/27"]
      enforce_private_link_endpoint_network_policies  = true
      enforce_private_link_service_network_policies   = true
    }      
  }      
}

resource "azurerm_network_security_group" "app-gateway-nsg" {
  name                = "app-gateway-nsg"
  location            = module.resource-group.location
  resource_group_name = module.resource-group.name  
}

resource "azurerm_network_security_rule" "lnrsvpnallowhttpaccess" {
  name                        = "LNRSVPNAllowHttp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "${chomp(data.http.my_ip.body)}"
  destination_address_prefix  = "*"
  resource_group_name         = module.resource-group.name
  network_security_group_name = azurerm_network_security_group.app-gateway-nsg.name
}

resource "azurerm_network_security_rule" "allowgatewaymanager" {
  name                        = "AllowGatewayManagerAccess"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "65200-65535"
  source_address_prefix       = "GatewayManager"
  destination_address_prefix  = "*"
  resource_group_name         = module.resource-group.name
  network_security_group_name = azurerm_network_security_group.app-gateway-nsg.name
}

resource "azurerm_subnet_network_security_group_association" "app-gateway-subnet-nsg" {
  subnet_id                 = module.virtual_network.subnet["app-gateway"].id
  network_security_group_id = azurerm_network_security_group.app-gateway-nsg.id
}

```

**TIP**: Plan for the address space to accomodate the entire application. VMs, PaaS services VNet integration, Private Endpoints, etc.

**TIP**: PaaS VNet integration will mean that you will have to plan for dedicated subnets with IPs reserved. 

**TIP**: Azure reserves 5 IPs for every Subnet. Hence, the number of avaialble IPs = subnet address space total - 5 