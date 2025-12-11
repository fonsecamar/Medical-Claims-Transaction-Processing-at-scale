#!/usr/bin/pwsh

Param(
    [parameter(Mandatory=$true)][string]$resourceGroup
)

$synapsePath="..,..,synapse"
Push-Location $($MyInvocation.InvocationName | Split-Path)
Push-Location $(./Join-Path-Recursively.ps1 -pathParts $synapsePath.Split(","))

$workspaceName=$(az synapse workspace list -g $resourceGroup -o json 2>$null | ConvertFrom-Json).name
Write-Host "Configuring Synapse workspace: $workspaceName" -ForegroundColor White

Write-Host "  Creating linked services..." -ForegroundColor Gray
$lsResult = az synapse linked-service create --workspace-name $workspaceName --name CoreClaimsDataLake --file '@./linkedService/CoreClaimsDataLake.json' --only-show-errors 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "    ✗ CoreClaimsDataLake failed: $lsResult" -ForegroundColor Red; exit 1 }

$lsResult = az synapse linked-service create --workspace-name $workspaceName --name CoreClaimsCosmosDb --file '@./linkedService/CoreClaimsCosmosDb.json' --only-show-errors 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "    ✗ CoreClaimsCosmosDb failed: $lsResult" -ForegroundColor Red; exit 1 }

$lsResult = az synapse linked-service create --workspace-name $workspaceName --name solliancepublicdata --file '@./linkedService/solliancepublicdata.json' --only-show-errors 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "    ✗ solliancepublicdata failed: $lsResult" -ForegroundColor Red; exit 1 }

$datasets = Get-ChildItem ./dataset
Write-Host "  Creating $($datasets.Count) datasets..." -ForegroundColor Gray
$datasetCount = 0
foreach ($dataset in $datasets) {
    $name = $dataset.BaseName
    $fileName = "@./dataset/$($dataset.Name)"
    $dsResult = az synapse dataset create --workspace-name $workspaceName --name "${name}" --file $fileName --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    ✗ Dataset $name failed: $dsResult" -ForegroundColor Red
        exit 1
    }
    $datasetCount++
    if ($datasetCount % 5 -eq 0) {
        Write-Host "    $datasetCount/$($datasets.Count) datasets created" -ForegroundColor DarkGray
    }
}
Write-Host "  ✓ All datasets created" -ForegroundColor Green

Write-Host "  Creating ingestion pipeline..." -ForegroundColor Gray
$pipelineResult = az synapse pipeline create --workspace-name $workspaceName --file '@./pipeline/Initial-Ingestion.json' --name Initial-Ingestion --only-show-errors 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ Pipeline creation failed: $pipelineResult" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Pipeline created" -ForegroundColor Green

Pop-Location
Pop-Location
