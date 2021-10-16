<#
Copyright © 2021 Michael Lopez

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.SYNOPSIS

This cmdlet will copy a given Azure Policy assignment for an Azure Policy Initiative (policySetDefinition)

.DESCRIPTION

The cmdlet is a result of a particular scenario where a user may need to copy an entire initiative to a higher scope as it would require to move the definitions, the policy set and the assignment together.
This cmdlet will iterate over all the resources and hierarchy and do a best-effort copy of all hierarchy to the new scope.

It's important to note, this script does not work with assignments that use PolicyDefinitionGroups at this time.

.PARAMETER AssignmentId

Provide the Azure Policy Initiative assignment ID.

.PARAMETER DestinationScope

Provide on which scope this particular Azure Policy Initiative assignment will be copied to

.INPUTS

None. This cmdlet does not support inputs

.OUTPUTS

A data structure containing two properties

OldValue: Resource ID that was copied from.
NewValue: Resource ID that was copied to.

.EXAMPLE

The following copies an Azure Policy Initiative from a source Management Group to its parent Management Group.
We are assuming parentManagementGroup is a parent Management Group to childManagementGroup


Import-Module .\Copy-AzInitiative.ps1
Copy-AzInitiative -AssignmentId /providers/Microsoft.Management/managementGroups/childManagementGroup/Microsoft.Authorization/policyAssignments/sourcePolicyAssignment `
    -DestinationScope /providers/Microsoft.Management/managementGroups/parentManagementGroup

.EXAMPLE

The following copies an Azure Policy Initiative from a source subscription to a Management Group

Import-Module .\Copy-AzInitiative.ps1
Copy-AzInitiative -AssignmentId /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/providers/Microsoft.Authorization/policyAssignments/sourcePolicyAssignment `
    -DestinationScope /providers/Microsoft.Management/managementGroups/managementGroup

#>
function Copy-AzInitiative {
    [CmdletBinding()]
    param (
        [String][Parameter(Mandatory=$true)]$AssignmentId,
        [String][Parameter(Mandatory=$true)]$DestinationScope
    )

    $context = Get-AzContext
    $command = $MyInvocation.MyCommand
    $originalProgress = $ProgressPreference
    
    if($null -eq $context -or $null -eq $context.Account) {
        throw New-Object -TypeName PSInvalidOperationException "$command : Run Connect-AzAccount to login."
    }

    $assignment = Get-AzPolicyAssignment -Id $AssignmentId

    if($assignment.Scope -eq $DestinationScope) {
        #If the destination scope is the same, why continue?
        return
    }

    $policySetDefinitionId = $assignment.Properties.PolicyDefinitionId
    $policySet = Get-AzPolicySetDefinition -Id $policySetDefinitionId -ErrorAction SilentlyContinue
    if($null -eq $policySet) {
        # TODO: This script assumes that the assignment is for a policy set definition, not for a policy definition, we may need to add a branch to consider the opposite use-case
        throw New-Object -TypeName PSArgumentOutOfRangeException -ArgumentList "$command : At this time, this cmdlet only expects policySetDefinition assignments."
    }
    $isManagementGroup = $DestinationScope.StartsWith("/providers/Microsoft.Management/managementGroups/")
    $managemengGroupName = $null
    $subscriptionId = $null
    $match = $null
    if($isManagementGroup) {
        $managemengGroupName = $DestinationScope.Replace("/providers/Microsoft.Management/managementGroups/", "")
    } else {
        $match = [Text.RegularExpressions.Regex]::Match($DestinationScope, "^\/subscriptions\/([a-fA-F0-9]{8}\-([a-fA-F0-9]{4}\-){3}[a-fA-F0-9]{12})[\/.*|$]")
        $subscriptionId = $match.Groups[1]
        if(-not $match.Success) {
            $errorMsg = "The Destination Scope '$($DestinationPolicy) could not be parsed as a Management Group nor a Subscription ID"
            throw New-Object -TypeName PSArgumentOutOfRangeException -ArgumentList "$command : $($errorMsg)"
        }
    }

    $oldToNewMap = [System.Collections.Generic.Dictionary[String, String]]::new()
    $newPolicies = [System.Collections.ArrayList]::new()

    $policySet.Properties.PolicyDefinitions | ForEach-Object {
        $policy = Get-AzPolicyDefinition -Id $_.PolicyDefinitionId
        $copyMetadata = $policy.Properties.Metadata | ConvertTo-Json -Depth 100
        $copyParameters = $policy.Properties.Parameters | ConvertTo-Json -Depth 100
        $copyPolicy = $policy.Properties.PolicyRule | ConvertTo-Json -Depth 100
        $newPolicy = $null

        $ProgressPreference = "SilentlyContinue"
        try {
            if($isManagementGroup) {
                $newPolicy = New-AzPolicyDefinition -Name $policy.Name -DisplayName $policy.Properties.DisplayName -Description $policy.Properties.Description -Policy $copyPolicy `
                    -Metadata $copyMetadata -Parameter $copyParameters -Mode $policy.Properties.Mode -ManagementGroupName $managemengGroupName
            }
            elseif($null -ne $match -and $match.Success) {
                $newPolicy = New-AzPolicyDefinition -Name $policy.Name -DisplayName $policy.Properties.DisplayName -Description $policy.Properties.Description -Policy $copyPolicy `
                    -Metadata $copyMetadata -Parameter $copyParameters -Mode $policy.Properties.Mode -SubscriptionId $subscriptionId
            }
        }
        finally {
            $ProgressPreference = $originalProgress
        }

        if($null -ne $newPolicy) {
            $oldToNewMap.Add($newPolicy.ResourceId, $policy.ResourceId)
            $newPolicies.Add($newPolicy) | Out-Null
        }
    }

    $newPolicySetMetadata = $policySet.Properties.Metadata | ConvertTo-Json -Depth 100
    $newPolicySetParameters = $policySet.Properties.Parameters | ConvertTo-Json -Depth 100
    $newPolicySetPolicy = New-Object System.Collections.ArrayList

    $newPolicies | ForEach-Object {
        $newPol = $_
        $oldPolId = $oldToNewMap[$_.ResourceId]
        $original = $policySet.Properties.PolicyDefinitions | Where-Object { $_.policyDefinitionId -eq $oldPolId } | Select-Object -First 1
        $clone = $original | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $clone.policyDefinitionId = $newPol.ResourceId
        $newPolicySetPolicy.Add($clone) | Out-Null
    }

    $newPolicySetPolicy = $newPolicySetPolicy | ConvertTo-Json -Depth 100
    $newPolicySet = $null

    $ProgressPreference = "SilentlyContinue"
    try {
        if($isManagementGroup) {
            $newPolicySet = New-AzPolicySetDefinition -Name $policySet.Name -DisplayName $policySet.Properties.DisplayName -Description $policySet.Properties.Description `
                -Metadata $newPolicySetMetadata -Parameter $newPolicySetParameters -PolicyDefinition $newPolicySetPolicy -ManagementGroupName $managemengGroupName
        }
        elseif($null -ne $match -and $match.Success) {
            $newPolicySet = New-AzPolicySetDefinition -Name $policySet.Name -DisplayName $policySet.Properties.DisplayName -Description $policySet.Properties.Description `
                -Metadata $newPolicySetMetadata -Parameter $newPolicySetParameters -PolicyDefinition $newPolicySetPolicy -SubscriptionId $subscriptionId
        }
    }
    finally {
        $ProgressPreference = $originalProgress
    }

    if($null -ne $newPolicySet) {
        $oldToNewMap.Add($newPolicySet.ResourceId, $policySet.ResourceId)
    }

    $newAssignmentParamater = $assignment.Properties.Parameters | ConvertTo-Json -Depth 100
    $newAssignmentMetadata = $assignment.Properties.Metadata | ConvertTo-Json -Depth 100
    $notScopes = $assignment.Properties.NotScopes
    if($null -eq $notScopes) {
        $notScopes = @()
    }

    $ProgressPreference = "SilentlyContinue"
    try {
        if($null -eq $assignment.Properties.NotScopes) {
            $newAssignment = New-AzPolicyAssignment -Name $assignment.Name -Scope $DestinationScope `
                -DisplayName $assignment.Properties.DisplayName -Description $assignment.Properties.Description -PolicySetDefinition $newPolicySet `
                -PolicyParameter $newAssignmentParamater -EnforcementMode $assignment.Properties.EnforcementMode -Metadata $newAssignmentMetadata
        }
        else {
            $newAssignment = New-AzPolicyAssignment -Name $assignment.Name -Scope $DestinationScope -NotScope $assignment.Properties.NotScopes `
                -DisplayName $assignment.Properties.DisplayName -Description $assignment.Properties.Description -PolicySetDefinition $newPolicySet `
                -PolicyParameter $newAssignmentParamater -EnforcementMode $assignment.Properties.EnforcementMode -Metadata $newAssignmentMetadata
        }
    }
    finally {
        $ProgressPreference = $originalProgress
    }

    if($null -ne $newAssignment) {
        $oldToNewMap.Add($newAssignment.ResourceId, $assignment.ResourceId)
    }
    
    if($oldToNewMap.Keys.Count -gt 0) {
        $oldToNewMap.Keys | ForEach-Object {
            $lastObj = New-Object -Type PSCustomObject
            $lastObj | Add-Member -MemberType NoteProperty -Name OldValue -Value $oldToNewMap[$_] -Force
            $lastObj | Add-Member -MemberType NoteProperty -Name NewValue -Value $_ -Force

            $lastObj
        }
    }
}
