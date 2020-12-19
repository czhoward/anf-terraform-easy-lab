# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.37"
    }
  }
}

provider "azurerm" {
  features {}
}

# Core Azure resources/configuration

resource "azurerm_resource_group" "tf-group" {
  name     = "tf-group"
  location = var.region
}

resource "azurerm_virtual_network" "tf-vnet" {
  name                = "tf-vnet"
  resource_group_name = azurerm_resource_group.tf-group.name
  location            = azurerm_resource_group.tf-group.location
  address_space       = ["20.0.0.0/16"]
}

# subnet for VMs
resource "azurerm_subnet" "vms" {
  name                 = "vms"
  resource_group_name  = azurerm_resource_group.tf-group.name
  virtual_network_name = azurerm_virtual_network.tf-vnet.name
  address_prefixes     = ["20.0.1.0/24"]
}

# Provision public IP for the Windows AD server
resource "azurerm_public_ip" "tf-win-ad-01-public-ip" {
  name                = "tf-linux-win-ad-01-public-ip"
  location            = azurerm_resource_group.tf-group.location
  resource_group_name = azurerm_resource_group.tf-group.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "Terraform Demo"
  }
}

# Provision and configure the NIC interface for the Windows AD server
resource "azurerm_network_interface" "tf-win-ad-01-nic-01" {
  name                          = "tf-win-ad-01-nic-01"
  location                      = azurerm_resource_group.tf-group.location
  resource_group_name           = azurerm_resource_group.tf-group.name
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "20.0.1.100"
    public_ip_address_id          = azurerm_public_ip.tf-win-ad-01-public-ip.id
  }
}

# Create the NSG for the Windows AD server
resource "azurerm_network_security_group" "tf-win-ad-01-nsg" {
  name                = "tf-win-ad-01-nsg"
  location            = azurerm_resource_group.tf-group.location
  resource_group_name = azurerm_resource_group.tf-group.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Terraform Demo"
  }
}

# Provision the Windows AD server VM
resource "azurerm_windows_virtual_machine" "tf-win-ad-01" {
  name                = "ad01"
  resource_group_name = azurerm_resource_group.tf-group.name
  location            = azurerm_resource_group.tf-group.location
  size                = "Standard_D4s_v3"
  admin_username      = var.username
  admin_password      = var.password
  network_interface_ids = [
    azurerm_network_interface.tf-win-ad-01-nic-01.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

# Connect the security group to the network interface (Enable onnectivity)
resource "azurerm_network_interface_security_group_association" "tf-nsg-asso-02" {
  network_interface_id      = azurerm_network_interface.tf-win-ad-01-nic-01.id
  network_security_group_id = azurerm_network_security_group.tf-win-ad-01-nsg.id
}

# modified from
# https://registry.terraform.io/modules/ghostinthewires/promote-dc/azurerm/latest?tab=resources
# https://github.com/ghostinthewires/terraform-azurerm-promote-dc/blob/master/main.tf
// the `exit_code_hack` is to keep the VM Extension resource happy
locals { 
  import_command       = "Import-Module ADDSDeployment, ActiveDirectory"
  password_command     = "$password = ConvertTo-SecureString ${var.password} -AsPlainText -Force"
  install_ad_command   = "Add-WindowsFeature -name ad-domain-services -IncludeManagementTools"
  configure_ad_command = "Install-ADDSForest -CreateDnsDelegation:$false -DomainMode Win2012R2 -DomainName ${var.domainname} -DomainNetbiosName ${var.adnetbiosname} -ForestMode Win2012R2 -InstallDns:$true -SafeModeAdministratorPassword $password -Force:$true"
  shutdown_command     = "shutdown -r -t 10"
  exit_code_hack       = "exit 0"
  powershell_command   = "${local.import_command}; ${local.password_command}; ${local.install_ad_command}; ${local.configure_ad_command}; ${local.shutdown_command}; ${local.exit_code_hack}"
}

resource "azurerm_virtual_machine_extension" "create-active-directory-forest" {
  name                 = azurerm_windows_virtual_machine.tf-win-ad-01.name
  virtual_machine_id   = azurerm_windows_virtual_machine.tf-win-ad-01.id

  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
    {
        "commandToExecute": "powershell.exe -Command \"${local.powershell_command}\""
    }
SETTINGS

  tags = {
    environment = "Terraform Demo"
  }

  depends_on = [
    azurerm_windows_virtual_machine.tf-win-ad-01
  ]
}

# Create a Public IP address for the network

resource "azurerm_public_ip" "tf-linux-vm-01-public-ip" {
  name                = "tf-linux-vm-01-public-ip"
  location            = azurerm_resource_group.tf-group.location
  resource_group_name = azurerm_resource_group.tf-group.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "Terraform Demo"
  }
}


# Create an NSG for SSH to the Linux VM

resource "azurerm_network_security_group" "tf-linux-vm-01-nsg" {
  name                = "tf-linux-vm-01-nsg"
  location            = azurerm_resource_group.tf-group.location
  resource_group_name = azurerm_resource_group.tf-group.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Terraform Demo"
  }
}

# Create Network Interface for Linux VM

resource "azurerm_network_interface" "tf-linux-vm-nic-01" {
  name                          = "tf-linux-vm-nic-01"
  location                      = azurerm_resource_group.tf-group.location
  resource_group_name           = azurerm_resource_group.tf-group.name
  enable_accelerated_networking = true

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vms.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.tf-linux-vm-01-public-ip.id
  }

  tags = {
    environment = "Terraform Demo"
  }
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "tf-nsg-asso-01" {
  network_interface_id      = azurerm_network_interface.tf-linux-vm-nic-01.id
  network_security_group_id = azurerm_network_security_group.tf-linux-vm-01-nsg.id
}

# Create (and display) an SSH key
resource "tls_private_key" "tf_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
output "tls_private_key" { value = tls_private_key.tf_ssh.private_key_pem }

# Create the Virtual Machine
resource "azurerm_linux_virtual_machine" "tf-linux-vm-01" {
  name                            = "tf-linux-vm-01"
  resource_group_name             = azurerm_resource_group.tf-group.name
  location                        = azurerm_resource_group.tf-group.location
  size                            = "Standard_D4s_v3"
  admin_username                  = var.username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.tf-linux-vm-nic-01.id]

  admin_ssh_key {
    username   = "tf"
    public_key = tls_private_key.tf_ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  tags = {
    environment = "Terraform Demo"
  }
}
