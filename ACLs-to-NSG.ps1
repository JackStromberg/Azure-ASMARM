<#
*
* Author:	Jack Stromberg
* Email:	jstrom@microsoft.com
* Date:		9/8/2021
* Version:  1.5
* Docs: https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-acl-powershell
*
* Changelog
* v1.0 - Last Modified: 4/17/2018
* v1.1 - Last Modified: 4/23/2018 -- Fixed bug where NSG would overwrite itself
*                                    Added support for rules with a VM that has an NSG with some ACLs, but not on all
* v1.2 - Last Modified: 4/28/2018 -- Fixed translation of "Permit" to be "Allowed" per NSG rules
*								  -- If deny and permit rules are in the same ACL, added logic to add a Deny allow rule
* v1.3 - Last Modified: 8/31/2021 -- Added some additional logging
* v1.4 - Last Modified: 9/8/2021  -- Fixed issue with multiple VM endpoints
* v1.5 - Last Modified: 9/8/2021  -- Added parameter for skipping NSG rule creation (reuse existing NSG as-is)
*
* Caution:  Be careful about extended ASCII characters (Japanese/Chinese characters) as ASM/ARM migrations don't parse
*           these characters properly
*
* Assumptions:
*           This script assumes you have single NIC machines
*           This script will add additional rules if an NSG exists with the same name of <VMName>-NSG
*           
* Variables:
*           $ServiceName is the cloud service you want to want to translate ACLs to NSGs
*           $region is the region your cloud service is deployed to
*           $stripACLsAssociateNSGs = $True will remove ACLs and set the NSG to the cloud service (you will be prompted before removal)
*           $stripACLsAssociateNSGs = $False will create the NSG based on ACL rules but not associate it or remove the ACLs.
*           $skipNSGRuleCreation    = $True will use existing NSG as-is
*           $skipNSGRuleCreation    = $False will create/update existing NSG rules
#>

# Variables
$ServiceName = "Test7611"
$region = "East US"
$stripACLsAssociateNSGs = $False
$skipNSGRuleCreation    = $False

# Login to Azure
Add-AzureAccount

# Get list of VMs in CloudService
$VMs = Get-AzureVM –ServiceName $serviceName

foreach($vm in $VMs){
    Write-Host ("Getting endpoint info for VM {0}..." -f $vm.Name)

    # Get endpoints for each VM
    $endpoints = Get-AzureEndpoint -VM $vm
    if($endpoints.Count -gt 1){
        Write-Host ("{0} endpoints found for VM {1}...  Checking for ACLs..." -f $endpoints.Count,$vm.Name)
        $i = 1
        $priority = 200
        $aclsExist=0
        
        # Check if we need to build an NSG
        foreach($endpoint in $endpoints){
            if($endpoint.Acl.Count -gt 0){
                $aclsExist=1
            }
        }
        if($aclsExist -eq 0){
            Write-Host ("0 ACLs found for any endpoints on VM {0}...  Continueing on to next VM..." -f $vm.Name)
            continue
        }

        # Check if we should build a new NSG or use an existing
        $nsgName = $vm.Name + "-NSG"
        $nsg = Get-AzureNetworkSecurityGroup -Name $nsgName -ErrorAction SilentlyContinue
        if($nsg -eq $null){
            Write-Host "NSG did not exist, trying to create a new one..."
            $nsg = New-AzureNetworkSecurityGroup -Name $nsgName -Location $region
        }else{
            Write-Host ("Found existing NSG {0}, we will try to create rules for this NSG..." -f $nsgName)
        }

        # Build NSG Rules
        if($skipNSGRuleCreation -eq $False){
            foreach($endpoint in $endpoints){
                # Check if this endpoint has an ACL
                if($endpoint.Acl.Count -gt 0){
                    Write-Host ("{0} ACL(s) found for endpoint {1}... Checking for an existing NSG..." -f $endpoint.Acl.Count.ToString(),$endpoint.Name)

                    $acls = Get-AzureAclConfig -EndpointName $endpoint.Name -VM $vm -ErrorAction Stop
                    $hasPermits = $False # we will use this later to determine ACL rules
                    foreach($acl in $acls){
                        # Build NSG rule
                        $ruleName = "Rule-"+$i
                        $ActionType = (Get-Culture).TextInfo.ToTitleCase($acl.Action.ToLower())
                        if($ActionType -match "permit"){
                            $ActionType = "Allow"
                            $hasPermits = $True
                        }
                        Write-Host ("Adding NSG rule for {0} port {1} with Action {2}..." -f $endpoint.Protocol,$endpoint.LocalPort,$ActionType)
                        $nsg | Set-AzureNetworkSecurityRule -Name $ruleName -Action $ActionType -Protocol $endpoint.Protocol.ToUpper() -Type Inbound -Priority $priority -SourceAddressPrefix $acl.RemoteSubnet  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $endpoint.LocalPort
                        $priority+=1
                        $i++
                    }

                    # Creating NSG to allow all on this endpoint to simulate classic endpoint behavior
                    # https://docs.microsoft.com/en-us/azure/virtual-network/virtual-networks-acl#permit-and-deny
                    Write-Host ("Adding NSG rule to {0} all other source traffic Inbound on this NSG to simulate classic endpoint behavior..." -f $acls[0].Action)
                    $ruleName = "Rule-"+$i
                    if($acls[0].Action -eq "deny"){
                    
                        # For ACLs containing Deny, Permit statements, create a deny all rule; else create a default allow all rule
                        if($hasPermits -eq $True){
                            # Create default deny rule
                            $nsg | Set-AzureNetworkSecurityRule -Name $ruleName -Action "Deny" -Protocol $endpoint.Protocol.ToUpper() -Type Inbound -Priority $priority -SourceAddressPrefix INTERNET  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $endpoint.LocalPort
                        }else{
                            # Create default allow rule
                            $nsg | Set-AzureNetworkSecurityRule -Name $ruleName -Action "Allow" -Protocol $endpoint.Protocol.ToUpper() -Type Inbound -Priority $priority -SourceAddressPrefix INTERNET  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $endpoint.LocalPort
                        }
                        
                    }else{
                        # Create default deny rule
                        $nsg | Set-AzureNetworkSecurityRule -Name $ruleName -Action "Deny" -Protocol $endpoint.Protocol.ToUpper() -Type Inbound -Priority $priority -SourceAddressPrefix INTERNET  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $endpoint.LocalPort
                    }

                }else{
                    
                    Write-Host ("No ACLs for endpoint {0} on VM {1}... creating a default allow rule for the port" -f $endpoint.Name,$vm.Name)
                    # Create default allow rule
                    $ruleName = "Rule-"+$i
                    $nsg | Set-AzureNetworkSecurityRule -Name $ruleName -Action "Allow" -Protocol $endpoint.Protocol.ToUpper() -Type Inbound -Priority $priority -SourceAddressPrefix INTERNET  -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange $endpoint.LocalPort
                
                }

                # Increase priority by 10 to give us some room between last ACL rules and next endpoint
                $priority += 10
                $i++
            }
        }else{
            Write-Host "Skipping NSG rule creation/updates..."
        }

        # Strip out ACLs and add NSGs
        if($stripACLsAssociateNSGs -eq $True){
            Write-Host ("Please validate your NSG looks correct for VM {0}..." -f $vm.Name)
            
            # Validate we are ready to remove ACLs and attach NSG
            $answer = Read-Host "Once validated, do you wish to proceed with replacing ACLs with NSGs? [yes,no]"
            while("yes","no" -notcontains $answer)
            {
	            $answer = Read-Host "Invalid answer | Do you wish to proceed with replacing ACLs with NSGs? [yes,no]"
            }

            if($answer -eq "yes"){
                # Remove each ACL
                foreach($endpoint in $endpoints){
                    if($endpoint.Acl.Count -gt 0){
                        Write-Host ("Removing ACLs for {0}..." -f $endpoint.Name)
                        Remove-AzureAclConfig -EndpointName $endpoint.Name -VM $vm | Update-AzureVM
                    }
                }

                # Associate NSG to the Virtual Machine
		Write-Host ("Setting NSG {0} for VM {1}...!" -f $nsgName, $vm)
                Set-AzureNetworkSecurityGroupAssociation -Name $nsgName -VM $vm -ServiceName $ServiceName
            }else{
                Write-Host "Skipping removal of ACLs and attachment of NSG..."
            }
        }

    }else{
        Write-Host ("No Endpoints for {0}" -f $vm.Name)
    }    
}

Write-Host ("Script completed!")

# Migrate Resources to ARM
