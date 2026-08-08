<#
.SYNOPSIS
    Example script whose help comment mentions a fake dependency.
.DESCRIPTION
    #Requires -Modules FakeModule.FromComment
#>
#Requires -Modules Az.Real

param(
    [string]$ResourceGroup
)

Write-Host "Deploying to $ResourceGroup"
