<#
*
* Author:		Jack Stromberg
* Email:		jstrom@microsoft.com
* Date:		  8/24/2021
* Version:	1.0
*
* Changelog
* v1.0 - Initial Release
* v1.1 - Swapping ARM command: 8/26/2021
*
* Notes:
*       This is an example of installing a VM extension (BGinfo used as an example) post ASM -> ARM migration.
*
* Assumptions:
*       This is a manual installation of BGInfo extension. The following cmdlet could be used as well:
*       https://docs.microsoft.com/en-us/powershell/module/az.compute/set-azvmbginfoextension?view=azps-6.3.0
#>
Set-AzVMExtension -ExtensionName BGInfo -Publisher Microsoft.Compute -Version 2.1 -ExtensionType BGInfo -Location westus -ResourceGroupName YOUR_RESOURCE_GROUP -VMName YOUR_VM_NAME
