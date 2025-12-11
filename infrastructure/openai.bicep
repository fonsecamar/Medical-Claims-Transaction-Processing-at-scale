@description('OpenAI service name')
param openAiName string

@description('Resource location')
param location string = resourceGroup().location

@description('OpenAI deployments')
param deployments array = []

@description('API managed identity principal ID for RBAC')
param apiPrincipalId string

@description('Worker managed identity principal ID for RBAC')
param workerPrincipalId string

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2025-09-01' = {
  name: openAiName
  location: location
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
  sku: { name: 'S0' }
}

@batchSize(1)
resource openAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-09-01' = [for deployment in deployments: {
  parent: openAiAccount
  name: deployment.name
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.model
      version: deployment.version
    }
  }
  sku: deployment.?sku ?? {
    name: 'Standard'
    capacity: 10
  }
}]

// Cognitive Services OpenAI User role
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource apiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, apiPrincipalId, openAiUserRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource workerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, workerPrincipalId, openAiUserRoleId)
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output endpoint string = openAiAccount.properties.endpoint
output id string = openAiAccount.id
output name string = openAiAccount.name
