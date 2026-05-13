targetScope = 'managementGroup'

@minLength(36)
@maxLength(36)
@description('Tenant ID of the managing tenant')
param managingTenantId string

@description('Display name for the Lighthouse offer')
param lighthouseOfferName string = 'Managed Cloud Operations'

@description('Default location used for resources or deployments requiring a location parameter')
param location string = 'denmarkeast'

@description('The version number of the lighthouse deployment template')
param version string = '1.0.0'

@minLength(36)
@maxLength(36)
@description('Object ID of the service principal that will be executing all actions through Azure lighthouse')
param systemAgentPrincipalId string

@minLength(36)
@maxLength(36)
@description('Object ID of the security group or service principal with permanent Reader access for support purposes')
param supportTeamPrincipalId string

@minLength(36)
@maxLength(36)
@description('Object ID of the security group or service principal eligible for additional PIM-controlled access for support purposes')
param specialistTeamPrincipalId string

@description('Policy definition name')
param policyDefinitionName string = 'MC-Deploy-Azure-Lighthouse'

@description('Policy assignment name')
param policyAssignmentName string = 'MC-Deploy-Azure-Lighthouse-MG'

var roleIds = {
  // Used to grant permanent Reader access to the provider group or service principal, ensuring visibility of the subscription and its resources in the Azure portal and APIs.
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  // Used to grant permanent Contributor access to the provider group or service principal, allowing them to manage resources in the subscription.
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  // Used to grant cost management contributor access to the provider group or service principal.
  costManagementContributor: '434105ed-43f6-45c7-a02f-909b2ba83430'
  // Used to grant resource policy contributor access to the provider group or service principal.
  resourcePolicyContributor: '36243c78-bf99-498c-9df9-86d9f8d28608'
  // Used to grant User Access Administrator role to the policy assignment's managed identity, allowing it to assign the necessary roles to the service principals in the target subscriptions during deployment.
  userAccessAdministrator: '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
}

var principalNames = {
  supportTeam: 'Managed Cloud Operations Support'
  specialistTeam: 'Managed Cloud Operations Specialist'
  systemAgent: 'Managed Cloud Operations Agent'
}

var authorizations = [
  // System agent
  // - Contributor role is required to onboard the subscription to Lighthouse and manage resources within it.
  // - Resource Policy Contributor is required to assign resource policies at the subscription scope.
  // - Cost Management Contributor is required to view cost data in the Azure portal and APIs.
  {
    principalId: systemAgentPrincipalId
    principalIdDisplayName: '${principalNames.systemAgent} (Contributor)'
    roleDefinitionId: roleIds.contributor
  }
  {
    principalId: systemAgentPrincipalId
    principalIdDisplayName: '${principalNames.systemAgent} (Resource Policy Contributor)'
    roleDefinitionId: roleIds.resourcePolicyContributor
  }
  {
    principalId: systemAgentPrincipalId
    principalIdDisplayName: '${principalNames.systemAgent} (Cost Management Contributor)'
    roleDefinitionId: roleIds.costManagementContributor
  }
  // Support team
  {
    principalId: supportTeamPrincipalId
    principalIdDisplayName: '${principalNames.supportTeam} (Reader)'
    roleDefinitionId: roleIds.reader
  }
  // Specialist team
  {
    principalId: specialistTeamPrincipalId
    principalIdDisplayName: '${principalNames.specialistTeam} (Reader)'
    roleDefinitionId: roleIds.reader
  }
]

var eligibleAuthorizations = [
  {
    principalId: specialistTeamPrincipalId
    principalIdDisplayName: '${principalNames.specialistTeam} (Contributor)'
    roleDefinitionId: roleIds.contributor
    justInTimeAccessPolicy: {
      multiFactorAuthProvider: 'Azure'
      maximumActivationDuration: 'PT8H'
      // When empty, there is no approval requirement
      managedByTenantApprovers: []
    }
  }
  {
    principalId: specialistTeamPrincipalId
    principalIdDisplayName: '${principalNames.specialistTeam} (User Access Administrator)'
    roleDefinitionId: roleIds.userAccessAdministrator
    justInTimeAccessPolicy: {
      multiFactorAuthProvider: 'Azure'
      maximumActivationDuration: 'PT1H'
      // When empty, there is no approval requirement
      managedByTenantApprovers: []
    }
  }
]

var commonMetadata = {
  category: 'Lighthouse'
  version: version
  owner: principalNames.systemAgent
  createdBy: 'Bicep'
  deployment: 'ManagementGroup'
}

resource lighthousePolicy 'Microsoft.Authorization/policyDefinitions@2025-11-01' = {
  name: policyDefinitionName
  properties: {
    displayName: 'Deploy Azure Lighthouse delegation'
    policyType: 'Custom'
    mode: 'All'
    metadata: union(commonMetadata, {
      description: 'Ensures all subscriptions are onboarded to Azure Lighthouse'
    })
    parameters: {
      managingTenantId: { type: 'String' }
      lighthouseOfferName: { type: 'String' }
      authorizations: { type: 'Array' }
      eligibleAuthorizations: { type: 'Array' }
      location: { type: 'String' }
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
          // Ensures the policy assignment's managed identity automatically gets the required permissions at the subscription deployment scope when the policy runs
          roleDefinitionIds: [
            '/providers/Microsoft.Authorization/roleDefinitions/${roleIds.contributor}'
            '/providers/Microsoft.Authorization/roleDefinitions/${roleIds.userAccessAdministrator}'
          ]
          existenceCondition: {
            allOf: [
              // Checks if a registration assignment exists for the subscription with the expected registration definition ID and name.
              {
                field: 'Microsoft.ManagedServices/registrationAssignments/registrationDefinitionId'
                equals: '[resourceId(\'Microsoft.ManagedServices/registrationDefinitions\', guid(parameters(\'managingTenantId\'), parameters(\'lighthouseOfferName\')))]'
              }
              // Ensures the registration assignment is named according to the convention, which includes the subscription ID and lighthouseOfferName, to prevent conflicts and ensure idempotency.              
              {
                field: 'name'
                equals: '[guid(subscription().subscriptionId, parameters(\'lighthouseOfferName\'))]'
              }
            ]
          }
          deploymentScope: 'subscription'
          deployment: {
            location: '[parameters(\'location\')]'
            properties: {
              mode: 'Incremental'
              template: {
                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                contentVersion: '1.0.0.0'
                parameters: {
                  managingTenantId: { type: 'string' }
                  lighthouseOfferName: { type: 'string' }
                  authorizations: { type: 'array' }
                  eligibleAuthorizations: { type: 'array' }
                }
                resources: [
                  {
                    type: 'Microsoft.ManagedServices/registrationDefinitions'
                    apiVersion: '2022-10-01'
                    name: '[guid(parameters(\'managingTenantId\'), parameters(\'lighthouseOfferName\'))]'
                    properties: {
                      description: 'Delegated Azure management via Azure Lighthouse'
                      managedByTenantId: '[parameters(\'managingTenantId\')]'
                      registrationDefinitionName: '[parameters(\'lighthouseOfferName\')]'
                      authorizations: '[parameters(\'authorizations\')]'
                      eligibleAuthorizations: '[parameters(\'eligibleAuthorizations\')]'
                    }
                  }
                  {
                    type: 'Microsoft.ManagedServices/registrationAssignments'
                    apiVersion: '2022-10-01'
                    name: '[guid(subscription().subscriptionId, parameters(\'lighthouseOfferName\'))]'
                    properties: {
                      registrationDefinitionId: '[resourceId(\'Microsoft.ManagedServices/registrationDefinitions\', guid(parameters(\'managingTenantId\'), parameters(\'lighthouseOfferName\')))]'
                    }
                  }
                ]
              }
              parameters: {
                managingTenantId: { value: managingTenantId }
                lighthouseOfferName: { value: lighthouseOfferName }
                authorizations: { value: authorizations }
                eligibleAuthorizations: { value: eligibleAuthorizations }
                location: { value: location }
              }
            }
          }
        }
      }
    }
  }
}

resource lighthouseAssignment 'Microsoft.Authorization/policyAssignments@2025-11-01' = {
  name: policyAssignmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Deploy Azure Lighthouse to all subscriptions'
    description: 'Automatically deploys Azure Lighthouse delegation to all subscriptions under this management group.'
    policyDefinitionId: lighthousePolicy.id
    enforcementMode: 'Default'
    metadata: union(commonMetadata, {
      description: 'Automatically deploys Azure Lighthouse delegation to all subscriptions under this management group'
    })
    parameters: {
      managingTenantId: { value: managingTenantId }
      lighthouseOfferName: { value: lighthouseOfferName }
      authorizations: { value: authorizations }
      eligibleAuthorizations: { value: eligibleAuthorizations }
      location: { value: location }
    }
  }
}


// Required because Contributor does not allow assigning RBAC roles in all contexts.
// UAA is required for delegating roles to Lighthouse principals.
resource policyIdentityContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(
    managementGroup().id,
    lighthouseAssignment.id,
    roleIds.contributor
  )
  properties: {
    roleDefinitionId: '${managementGroup().id}/providers/Microsoft.Authorization/roleDefinitions/${roleIds.contributor}'
    principalId: lighthouseAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource policyIdentityUserAccessAdministrator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(
    managementGroup().id,
    lighthouseAssignment.id,
    roleIds.userAccessAdministrator
  )
  properties: {
    roleDefinitionId: '${managementGroup().id}/providers/Microsoft.Authorization/roleDefinitions/${roleIds.userAccessAdministrator}'
    principalId: lighthouseAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
