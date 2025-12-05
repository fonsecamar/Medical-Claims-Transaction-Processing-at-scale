#!/usr/bin/pwsh

Param(
    [parameter(Mandatory=$true)][string]$resourceGroup,
    [parameter(Mandatory=$true)][string]$location,
    [parameter(Mandatory=$true)][string]$suffix,
    [parameter(Mandatory={-not $deployAks})][string]$openAiName,
    [parameter(Mandatory={-not $deployAks})][string]$openAiCompletionsDeployment,
    [parameter(Mandatory={-not $deployAks})][string]$openAiRg,
    [parameter(Mandatory=$true)][bool]$deployAks
)

Push-Location $($MyInvocation.InvocationName | Split-Path)
$sourceFolder=$(Join-Path -Path ../.. -ChildPath infrastructure)

Write-Host "--------------------------------------------------------" -ForegroundColor Yellow
Write-Host "Deploying Bicep script $script" -ForegroundColor Yellow
Write-Host "-------------------------------------------------------- " -ForegroundColor Yellow
$env:BICEP_RESOURCE_TYPED_PARAMS_AND_OUTPUTS_EXPERIMENTAL="true"
$rg = $(az group show -n $resourceGroup -o json | ConvertFrom-Json)
if (-not $rg) {
    Write-Host "Creating resource group $resourceGroup in $location" -ForegroundColor Yellow
    az group create -n $resourceGroup -l $location
}

Write-Host "Beginning the Bicep deployment..." -ForegroundColor Yellow

# Get current user's principal ID for storage permissions
Write-Host "Getting current user principal ID..." -ForegroundColor Cyan
$currentUser = az ad signed-in-user show --query id -o tsv

Push-Location $sourceFolder

if ($deployAks) {
    $script="aksmain.bicep"
    Write-Host "Deploying AKS infrastructure..." -ForegroundColor Cyan
    az deployment group create -g $resourceGroup --template-file $script --parameters suffix=$suffix --parameters deployerPrincipalId=$currentUser
    $deploymentState = $(az deployment group show -g $resourceGroup -n $script.Replace('.bicep','') --query "properties.provisioningState" -o tsv)
} else {
    $script="acamain.bicep"
    Write-Host "Deploying ACA infrastructure..." -ForegroundColor Cyan
    az deployment group create -g $resourceGroup --template-file $script --parameters suffix=$suffix --parameters openAiName=$openAiName --parameters openAiDeployment=$openAiCompletionsDeployment --parameters openAiRg=$openAiRg --parameters deployerPrincipalId=$currentUser
    $deploymentState = $(az deployment group show -g $resourceGroup -n $script.Replace('.bicep','') --query "properties.provisioningState" -o tsv)
}

Write-Host "Deployment state: $deploymentState" -ForegroundColor $(if ($deploymentState -eq 'Succeeded') { 'Green' } else { 'Red' })

Pop-Location
Pop-Location