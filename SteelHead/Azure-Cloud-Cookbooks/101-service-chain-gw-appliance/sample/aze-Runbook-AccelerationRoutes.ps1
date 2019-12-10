<#

    .DESCRIPTION
        Riverbed Community Toolkit
        Cloud Community Cookbooks for Acceleration in Azure

        Set or Bypass Acceleration Routes, attaching/detaching Route Tables to subnets: transit, servernetwork and acceleration.

        This is a script template to be used as a PowerShell Runbook. It requires configuration in the Customization region, setting variables for VNET, resource group, routes details.

        By default , the execution of the script will enable acceleration attaching Acceleration Route Tables.
        Setting parameter $BypassAcceleration will detach acceleration route tables and attach bypass routes instead.
    
    Usage in Azure Automation Runbook

        Requirements in Automation Account, Shared Resources
        * Modules: Az.Accounts, Az.Automation, Az.Network
        * Connections: AzureRunAsAccount

        Runbook definition
        * name: Set-AccelerationRoutes
        * type: PowerShell
        * description: Set or Bypass Acceleration
        * edit PowerShell runbook: copy and paste, configure the Customization region if needed
        * Save and Publish

    .EXAMPLE
        
        # Set acceleration
        Run job without parameters to enable Acceleration

    .EXAMPLE
        
        # Bypass Acceleration 
        Run job with BypassAcceleration = true  ("true" is correct. It is not "$true", as there Azure PowerShell RunBook does not take $ sign)

    .EXAMPLE
        
        # Verbose
        Run job with Verbose = true
#>

# parameters
param(
    [switch][bool]$BypassAcceleration  = $false,
    [switch][bool]$Verbose  = $false, 
    [switch][bool]$WhatIf  = $false
)

#region Customization
$virtualNetworkName = "aze-hub-westeurope" # VNET, ex. "azu-hub-westus"
$virtualNetworkResourceGroupName = "aze-hub-westeurope"  # ex. "azu-hub-westus"

$AccelerationRoutes = @{
    servernetwork = @{
        AddressPrefix = "10.3.1.0/24" # ex. "10.1.1.0/24"
        RouteTableId = "/subscriptions/ccb776b6-aac4-4979-8e61-3d0cdb42ac19/resourceGroups/aze-acceleration-westeurope/providers/Microsoft.Network/routeTables/aze-servernetwork-ACCELERATION" # ex. "/subscriptions/1234-12341243-1243-12341324/resourceGroups/azu-acceleration/providers/Microsoft.Network/routeTables/azu-servernetwork-ACCELERATION"
    }
    transit = @{
        AddressPrefix = "10.3.0.0/24" # ex. "10.1.0.0/24"
        RouteTableId = "/subscriptions/ccb776b6-aac4-4979-8e61-3d0cdb42ac19/resourceGroups/aze-acceleration-westeurope/providers/Microsoft.Network/routeTables/aze-transit-ACCELERATION" # ex."/subscriptions/1234-12341243-1243-12341324/resourceGroups/azu-acceleration/providers/Microsoft.Network/routeTables/azu-transit-ACCELERATION"
    }
    acceleration = @{
        AddressPrefix = "10.3.82.0/24" # ex. "10.3.82.0/24"
        RouteTableId = "/subscriptions/ccb776b6-aac4-4979-8e61-3d0cdb42ac19/resourceGroups/aze-acceleration-westeurope/providers/Microsoft.Network/routeTables/aze-acceleration" # ex."/subscriptions/1234-12341243-1243-12341324/resourceGroups/azu-acceleration/providers/Microsoft.Network/routeTables/azu-acceleration"
    }
}

$BypassRoutes = @{
    servernetwork = @{
        AddressPrefix = "10.3.1.0/24" # ex. "10.1.1.0/24"
        RouteTableId = "/subscriptions/ccb776b6-aac4-4979-8e61-3d0cdb42ac19/resourceGroups/aze-acceleration-westeurope/providers/Microsoft.Network/routeTables/aze-servernetwork" # ex. "/subscriptions/1234-12341243-1243-12341324/resourceGroups/azu-acceleration/providers/Microsoft.Network/routeTables/azu-servernetwork"
    }
    transit = @{
        AddressPrefix = "10.3.0.0/24" # ex. "10.1.0.0/24"
        RouteTableId = ""  # ex. empty to detach the Route Table
    }
}

#endregion

#region lib

Import-Module Az.Accounts
Import-Module Az.Network
Import-Module Az.Automation

try
{
    $connectionName = "AzureRunAsConnection"
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch 
{
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName failed."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

#endregion


#variables
$routes = $AccelerationRoutes
if ($BypassAcceleration) {
    $routes = $BypassRoutes
}

$vnet = Get-AzVirtualNetwork -ResourceGroupName $virtualNetworkResourceGroupName -Name $virtualNetworkName

#verbose
if ($Verbose) {
    # Check subnet name, prefix and route table id
    Write-Output "-----------------"
    Write-Output "INITIAL STATE"
    Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | % { "$($_.Name) ,  $($_.AddressPrefix) , $($_.RouteTable.Id)" }

    Write-Output "-----------------"

    if ($BypassAcceleration) { Write-Output "BYPASS ACCELERATION ROUTES:" } 
    else { Write-Output "SET ACCELERATION ROUTES:" } 

    foreach ($subnetName in $routes.Keys) { "$subnetName $($routes[$subnetName].AddressPrefix ; $routes[$subnetName].RouteTableId)"  }
}

# Prepare and apply config on the vnet
foreach ($subnetName in $routes.Keys) { 
    $routeTableId = $routes[$subnetName].RouteTableId
    $addressPrefix = $routes[$subnetName].AddressPrefix
    if (!$routeTableId) {
        #Disassociate"
        $subnet = ($vnet.Subnets | Where-Object { $_.Name -eq $subnetName })
        $subnet.RouteTable = $null
    }
    else {
       # Prepare config to associate Route tables to subnets
       $output = Set-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $subnetName -AddressPrefix $addressPrefix -RouteTableId $routeTableId -WarningAction SilentlyContinue
    }
}

#verbose
if ($Verbose) {
    # Check subnet name, prefix and route table id
    Write-Output "-----------------"
    Write-Output "VNET NEW CONFIG TO APPLY"
    Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | % { "$($_.Name) ,  $($_.AddressPrefix) , $($_.RouteTable.Id)" }
}

# Apply
if (!$WhatIf) {
    Write-Output "-----------------"
    Write-Output "APLYING VNET NEW CONFIG"
    $output = Set-AzVirtualNetwork -VirtualNetwork $vnet
}

#verbose
if ($Verbose) {
    # Check subnet name, prefix and route table id
    Write-Output "-----------------"
    Write-Output "END STATE"
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $virtualNetworkResourceGroupName -Name $virtualNetworkName
    Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnet | % { "$($_.Name) ,  $($_.AddressPrefix) , $($_.RouteTable.Id)" }
}
