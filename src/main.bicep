targetScope = 'managementGroup'

@description('Tenant ID of the managing tenant')
param managedByTenantId string

@description('Display name for the Lighthouse offer')
param managedByName string = 'Managed Cloud Operations'

@description('Object ID of the service principal with permanent Contributor access')
param systemPrincipalId string

@description('Object ID of the provider group or service principal with permanent Reader access')
param readerPrincipalId string

@description('Object ID of the provider group or service principal eligible for PIM Contributor')
param contributorPrincipalId string

@description('Policy definition name')
param policyDefinitionName string = 'MC-Deploy-Azure-Lighthouse'

@description('Policy assignment name')
param policyAssignmentName string = 'MC-Deploy-Azure-Lighthouse-MG'

var authorizations = [
  {
    principalId: systemPrincipalId
    principalIdDisplayName: 'Managed Cloud Operations Agent'
    roleDefinitionId: 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
  }
  {
    principalId: readerPrincipalId
    principalIdDisplayName: 'Managed Cloud Operations (Reader)'
    roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  }
]

var eligibleAuthorizations = [
  {
    principalId: contributorPrincipalId
    principalIdDisplayName: 'Managed Cloud Operations (Contributor)'
    roleDefinitionId: 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
    justInTimeAccessPolicy: {
      multiFactorAuthProvider: 'Azure'
      maximumActivationDuration: 'PT8H'
      managedByTenantApprovers: []
    }
  }
]

resource lighthousePolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: policyDefinitionName
  properties: {
    displayName: 'Deploy Azure Lighthouse delegation'
    policyType: 'Custom'
    mode: 'All'
    parameters: {
      managedByTenantId: { type: 'String' }
      managedByName: { type: 'String' }
      authorizations: { type: 'Array' }
      eligibleAuthorizations: { type: 'Array' }
    }
    policyRule: {
      if: {
        field: 'type'
        equals: 'Microsoft.Resources/subscriptions'
      }
      then: {
        effect: 'deployIfNotExists'
        details: {
          type: 'Microsoft.ManagedServices/registrationAssignments'
          deploymentScope: 'subscription'
          deployment: {
            properties: {
              mode: 'Incremental'
              template: {
                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                contentVersion: '1.0.0.0'
                parameters: {
                  managedByTenantId: { type: 'string' }
                  managedByName: { type: 'string' }
                  authorizations: { type: 'array' }
                  eligibleAuthorizations: { type: 'array' }
                }
                resources: [
                  {
                    type: 'Microsoft.ManagedServices/registrationDefinitions'
                    apiVersion: '2022-10-01'
                    name: '[guid(parameters(\'managedByTenantId\'), parameters(\'managedByName\'))]'
                    properties: {
                        description: 'Delegated Azure management via Azure Lighthouse'
                        managedByTenantId: '[parameters(\'managedByTenantId\')]'
                        registrationDefinitionName: '[parameters(\'managedByName\')]'
                        authorizations: '[parameters(\'authorizations\')]'
                        eligibleAuthorizations: '[parameters(\'eligibleAuthorizations\')]'
                    }
                  }
                  {
                    type: 'Microsoft.ManagedServices/registrationAssignments'
                    apiVersion: '2022-10-01'
                    name: '[guid(subscription().subscriptionId, parameters(\'managedByName\'))]'
                    properties: {
                      registrationDefinitionId: '[resourceId(\'Microsoft.ManagedServices/registrationDefinitions\', guid(parameters(\'managedByTenantId\'), parameters(\'managedByName\')))]'
                    }
                  }
                ]
              }
              parameters: {
                managedByTenantId: { value: managedByTenantId }
                managedByName: { value: managedByName }
                authorizations: { value: authorizations }
                eligibleAuthorizations: { value: eligibleAuthorizations }
              }
            }
          }
        }
      }
    }
  }
}

resource lighthouseAssignment 'Microsoft.Authorization/policyAssignments@2021-06-01' = {
  name: policyAssignmentName
  properties: {
    displayName: 'Deploy Azure Lighthouse to all subscriptions'
    policyDefinitionId: lighthousePolicy.id
    parameters: {
      managedByTenantId: { value: managedByTenantId }
      managedByName: { value: managedByName }
      authorizations: { value: authorizations }
      eligibleAuthorizations: { value: eligibleAuthorizations }
    }
  }
}
