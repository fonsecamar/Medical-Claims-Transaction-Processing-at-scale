
@description('Suffix for resource deployment')
param suffix string = uniqueString(resourceGroup().id)

@description('Location for resource deployment')
param location string = resourceGroup().location

@description('OpenAI service name')
param openAiName string = ''

@description('OpenAI deployment name')
param openAiDeployment string = 'completions'

@description('OpenAI resource group (defaults to current resource group)')
param openAiRg string = resourceGroup().name

@description('The principal ID of the deployer for storage permissions')
param deployerPrincipalId string = ''

var appName = 'coreclaims-${suffix}'
var serviceNames = {
  aks: replace('aks-${appName}', '-', '')
  cosmosDb: replace('db-${appName}', '-', '')
  functionApp: replace('fa-${appName}', '-', '')
  servicePlan: 'asp-${appName}'
  eventHub: replace('eh-${appName}', '-', '')
  storage: replace('adl-${appName}', '-', '')
  synapse: 'synapse-${appName}'
  identity: 'id-${appName}'
  webStorage: replace('web-${appName}', '-', '')
  openAi: 'openai-${appName}'
  apimi: 'mi-api-${appName}'
  workermi: 'mi-worker-${appName}'
  ai: 'ai-${appName}'
}

module storage 'storage.bicep' = {
  scope: resourceGroup()
  name: 'storageDeploy'
  params: {
    storageAccountName: serviceNames.storage
    location: location
    apiPrincipalId: apiIdentity.properties.principalId
    workerPrincipalId: workerIdentity.properties.principalId
  }
}

module cosmosDb 'cosmos.bicep' = {
  scope: resourceGroup()
  name: 'cosmosDeploy'
  params: {
    accountName: serviceNames.cosmosDb
    location: location
    apiPrincipalId: apiIdentity.properties.principalId
    workerPrincipalId: workerIdentity.properties.principalId
  }
}

module eventHub 'eventhub.bicep' = {
  scope: resourceGroup()
  name: 'eventHubDeploy'
  params: {
    eventHubNamespace: serviceNames.eventHub
    location: location
    apiPrincipalId: apiIdentity.properties.principalId
    workerPrincipalId: workerIdentity.properties.principalId
  }
}

#disable-next-line BCP179
module synapse 'synapse.bicep' = {
  scope: resourceGroup()
  name: 'synapseDeploy'
  params: {
    cosmosAccountName: serviceNames.cosmosDb
    storageAccountName: serviceNames.storage
    synapseServiceName: serviceNames.synapse
    location: location
  }
  dependsOn: [storage, cosmosDb]
}

module logAnalytics 'loganalytics.bicep' = {
  name: 'logAnalyticsDeploy'
  params: {
    name: appName
    location: location
  }
}

// Determine OpenAI configuration (idempotent - always creates if not exists)
var finalOpenAiName = !empty(openAiName) ? openAiName : serviceNames.openAi
var isExternalRg = openAiRg != resourceGroup().name

// Deploy OpenAI in same resource group (idempotent)
module openAi 'openai.bicep' = if (!isExternalRg) {
  name: 'openAiDeploy'
  params: {
    openAiName: finalOpenAiName
    location: location
    deployments: [
      {
        name: openAiDeployment
        model: 'gpt-4o'
        version: '2024-11-20'
      }
    ]
    apiPrincipalId: apiIdentity.properties.principalId
    workerPrincipalId: workerIdentity.properties.principalId
  }
}

// Deploy OpenAI in external resource group (idempotent)
module openAiExternal 'openai.bicep' = if (isExternalRg) {
  name: 'openAiExternalDeploy'
  scope: resourceGroup(openAiRg)
  params: {
    openAiName: finalOpenAiName
    location: location
    deployments: [
      {
        name: openAiDeployment
        model: 'gpt-4o'
        version: '2024-11-20'
      }
    ]
    apiPrincipalId: apiIdentity.properties.principalId
    workerPrincipalId: workerIdentity.properties.principalId
  }
}

module containerApps 'containerapp.bicep' = {
  name: 'conatinerApps'
  params: {
    aiConnectionString: logAnalytics.outputs.aiConnectionString
    cosmosEndpoint: cosmosDb.outputs.cosmosAccountEndpoint
    dataLakeAccountName: serviceNames.storage
    laWorkspaceId: logAnalytics.outputs.laWorkspaceId
    location: location
    name: appName
    openAiCompletionsDeployment: openAiDeployment
    openAiEndpoint: isExternalRg ? openAiExternal!.outputs.endpoint : openAi!.outputs.endpoint
    suffix: suffix
    workerClientId: workerIdentity.properties.clientId
    apiClientId: apiIdentity.properties.clientId
    apiMiId: apiIdentity.id
    workerMiId: workerIdentity.id
  }
}

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: serviceNames.apimi
  location: location
}

resource workerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: serviceNames.workermi
  location: location
}

module staticwebsite 'staticwebsite.bicep' = {
  name: 'staticwebsiteDeploy'
  params: {
    storageAccountName: serviceNames.webStorage
    location: location
    deployerPrincipalId: deployerPrincipalId
  }
}

// Outputs for Generate-Config (eliminates az cli calls)
output config object = {
  suffix: suffix
  cosmosEndpoint: cosmosDb.outputs.cosmosAccountEndpoint
  dataLakeEndpoint: 'https://${serviceNames.storage}.dfs.${environment().suffixes.storage}'
  dataLakeAccountName: serviceNames.storage
  eventHubNamespace: '${serviceNames.eventHub}.servicebus.windows.net'
  openAiEndpoint: isExternalRg ? openAiExternal!.outputs.endpoint : openAi!.outputs.endpoint
  openAiName: finalOpenAiName
  openAiRg: openAiRg
  openAiCompletionsDeployment: openAiDeployment
  apiClientId: apiIdentity.properties.clientId
  workerClientId: workerIdentity.properties.clientId
  publisherClientId: apiIdentity.properties.clientId
  tenantId: tenant().tenantId
  aiConnectionString: logAnalytics.outputs.aiConnectionString
  apiUrl: 'https://${containerApps.outputs.apiFqdn}/api'
  webappHostname: containerApps.outputs.apiFqdn
}

output staticWebsiteUrl string = staticwebsite.outputs.staticWebsiteUrl
