####
## This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.  
## THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, 
## INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  
## We grant You a nonexclusive, royalty-free right to use and modify the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that 
## You agree: (i) to not use Our name, logo, or trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on 
## Your software product in which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, 
## including attorneys' fees, that arise or result from the use or distribution of the Sample Code.
####
# https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-ps-migration-classic-resource-manager
# https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-migration-classic-resource-manager-deep-dive

# If you don't have the Azure PowerShell modules, run the following on your Win 8+ machine as an administrator
Install-Module Az
Install-Module Azure

# Login to Azure Subscription (Need both Classic and ARM context)
Login-AzAccount
Add-AzureAccount

# If using Azure Cloud Shell, you can authenticate via the following for Classic (Won't work if MFA is enabled)
#Install-Module Azure
#$secpasswd = ConvertTo-SecureString "PlainTextPassword" -AsPlainText -Force
#$mycreds = New-Object System.Management.Automation.PSCredential("username@domain.com", $secpasswd)
#Add-AzureAccount -Credential $mycreds

# Set default subscription for both environments
Get-AzSubscription 
Get-AzSubscription -SubscriptionId XXXXXXXXXXXXXXXXXXXX | Set-AzContext
Select-AzureSubscription -SubscriptionId XXXXXXXXXXXXXXXXXXXX

# Register the namespace - note this may take up to 5 mins
Register-AzResourceProvider -ProviderNamespace Microsoft.ClassicInfrastructureMigrate

# Verify registration was a success, should see "Registered"
Get-AzResourceProvider -ProviderNamespace Microsoft.ClassicInfrastructureMigrate

# Migrate the network and VMs
# Validate the VNET
Move-AzureVirtualNetwork -Validate -VirtualNetworkName $vnetName
	(Move-AzureVirtualNetwork -Validate -VirtualNetworkName $vnetName).ValidationMessages

# Prepare the VNET (can take a few minutes to generate shadow resources)
Move-AzureVirtualNetwork -Prepare -VirtualNetworkName $vnetName

# Abort migration if things don't look right
# Move-AzureVirtualNetwork -Abort -VirtualNetworkName $vnetName

# Migrate the VNET
Move-AzureVirtualNetwork -Commit -VirtualNetworkName $vnetName

## Prepare Azure Storage Account for migration 
# FYI: don't enable disk encryption after this if going to managed storage
$storageAccountName = "myStorageAccount"

Move-AzureStorageAccount -Prepare -StorageAccountName $storageAccountName

# Commit Azure Storage Account to migrate
Move-AzureStorageAccount -Commit -StorageAccountName $storageAccountName

## Migrate to managed storage
## https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-windows-migrate-to-managed-disks

# Migrate cloud services without a VNET to the new environments
$existingVnetRGName = "myResourceGroup"
$vnetName = "myVirtualNetwork"
$subnetName = "mySubNet"
$serviceName = "myCloudService"
$deploymentName = $serviceName

# Validate the migration
$validate = Move-AzureService -Validate -ServiceName $serviceName `
      -DeploymentName $deploymentName -UseExistingVirtualNetwork -VirtualNetworkResourceGroupName $existingVnetRGName -VirtualNetworkName $vnetName -SubnetName $subnetName
$validate.ValidationMessages

# Prepare the migration
Move-AzureService -Prepare -ServiceName $serviceName -DeploymentName $deploymentName `
  -UseExistingVirtualNetwork -VirtualNetworkResourceGroupName $existingVnetRGName `
  -VirtualNetworkName $vnetName -SubnetName $subnetName

# Abort migration if things don't look right
# Move-AzureService -Abort -ServiceName $serviceName -DeploymentName $deploymentName

# Migrate the cloud serviceName
Move-AzureService -Commit -ServiceName $serviceName -DeploymentName $deploymentName

###############################################
# Troubleshooting
###############################################
# Commands to replace/upgrade Diagnostics extension due to it being unresponsive
Get-AzureVMExtension -VM $VM -ExtensionName LinuxDiagnostic -Publisher Microsoft.Azure.Diagnostics
Set-AzureVMExtension -VM $VM -Publisher 'Microsoft.Azure.Diagnostics' -ExtensionName LinuxDiagnostic -Version 3.0 | Update-AzureVM