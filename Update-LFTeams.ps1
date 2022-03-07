<#
.SYNOPSIS
Add Relevant Teams to Laserfiche Forms using Job Class Descriptions from Escape
.DESCRIPTION
This Script Queries the Escape database for matching Job Class Descriptions,
and adds Teams, Team Members, Roles, etc t the Laserfiche Forms Database
.EXAMPLE
 .\Update-LFTeams.ps1 -EscapeServer EscapeServerName -EscapeDatabase EscapeDBName -EscapeCredential $escCred -LaserficheFormsInstance MyDBServerInstance -LaserficheFormsDatabase LF-Forms -LaserficheDBCredential $lfCred
.EXAMPLE
 .\Update-LFTeams.ps1 -EscapeServer EscapeServerName -EscapeDatabase EscapeDBName -EscapeCredential $escCred -LaserficheFormsInstance MyDBServerInstance -LaserficheFormsDatabase LF-Forms -LaserficheDBCredential $lfCred -Verbose -WhatIf
.INPUTS
.OUTPUTS
.NOTES
.LINK
#>

[cmdletbinding()]
param (
 # Escape Employee Server
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$EscapeServer,
 [Parameter(Mandatory = $true)]
 [string]$EscapeDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$EscapeCredential,
 # Laserfiche DB Server
 [Parameter(Mandatory = $true)]
 # [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [Alias('LFServer')]
 [string]$LaserficheFormsInstance,
 [Parameter(Mandatory = $true)]
 [Alias('LFDB')]
 [string]$LaserficheFormsDatabase,
 [Parameter(Mandatory = $true)]
 [Alias('LFCred')]
 [System.Management.Automation.PSCredential]$LaserficheDBCredential,
 [string[]]$JobClasses,
 # Run a Whatif on commands - no data will be changed
 [Alias('wi')]
	[switch]$WhatIf
)
function Add-Role {
 begin {
  $insertRoleTemplate = Get-Content -Path .\sql\insert-role.txt -Raw
 }
 process {
  $teamRole = $_ | Get-TeamRole
  $team = $_.SiteDescr | Get-Team
  if (-not($teamRole)) {
   if ($team) {
    Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.JobClassDescr, $team.name)
    $sql = $insertRoleTemplate -f $team.id, $_.JobClassDescr
    # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
    Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
    Write-Debug $MyInvocation.MyCommand.Name
    if (-not$WhatIf) {
     Invoke-Sqlcmd @lfFormsDBParams -Query $sql
    }
   }
  }
 }
}
function Add-Team {
 begin {
  $insertTeamTemplate = Get-Content -Path .\sql\insert-team.txt -Raw
 }
 process {
  # if the input is null then create a team matching the input
  $check = $_ | Get-Team
  if ($null -eq $check) {
   $sql = $insertTeamTemplate -f $_
   # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Write-Debug $MyInvocation.MyCommand.Name
   if (-not$WhatIf) {
    Invoke-Sqlcmd @lfFormsDBParams -Query $sql
   }
  }
 }
}
function Add-TeamMember {
 begin {
  $insertTeamMemberTemplate = Get-Content -Path .\sql\insert-team_member.txt -Raw
 }
 process {
  $check = $_ | Get-TeamMember
  $team = $_.SiteDescr | Get-Team
  $user = $_.EmailWork | Get-LFUser
  if (-not($check)) {
   if ( -not($user) -or -not($team) ) {
    $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
    Write-Warning ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars)
   }
   else {
    $msgVars = $MyInvocation.MyCommand.name, $user.user_id, $user.username, $user.email, $user.displayname, $team.name
    Write-Host ('{0},{1},{2},{3},{4},{5}' -f $msgVars) -Fore DarkMagenta
    $sql = $insertTeamMemberTemplate -f $user.user_id, $team.id
    # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
    Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
    Write-Debug $MyInvocation.MyCommand.Name
    if (-not$WhatIf) {
     Invoke-Sqlcmd @lfFormsDBParams -Query $sql
    }
   }
  }
 }
}
function Add-TeamMemberRoleMapping {
 begin {
  $insertTeamRoleMappingTemplate = Get-Content -Path .\sql\insert-team_member_team_role_mapping.txt -Raw
 }
 process {
  $teamRole = $_ | Get-TeamRole
  $teamMember = $_ | Get-TeamMember
  $check = $_ | Get-TeamMemberRoleMapping
  if (-not($check)) {
   if ( -not($teamRole) -or -not($teamMember) ) {
    $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
    Write-Warning ('{0},{1},{2},Missing role [{3}] or (team_member_id) id [{4}]' -f $msgVars)
   }
   else {
    $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
    Write-Host ('{0},{1},{2},Mapping role [{3}] to (team_member_id) id [{4}]' -f $msgVars) -Fore DarkMagenta
    $sql = $insertTeamRoleMappingTemplate -f $teamRole.id, $teamMember.id
    Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
    Write-Debug ($sql | Out-String)
    if (-not$WhatIf) {
     Invoke-Sqlcmd @lfFormsDBParams -Query $sql
    }
   }
  }
 }
}
function Format-Sql ($sql, $vars) {
 process {
  if (Test-Path -Path $sql) {
   $raw = Get-Content -Path $sql -Raw
   $raw -f $vars
  }
  else {
   $sql -f $vars
  }
  return
 }
}
function Get-EscapeUserByJobClass {
 begin {
  $escapeDBParams = @{
   Server     = $EscapeServer
   Database   = $EscapeDatabase
   Credential = $EscapeCredential
  }
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_) -Fore Green
  $job = $_
  $properties = 'EmailWork,JobClassDescr,EmploymentStatusIsActive,SiteId,SiteDescr'
  $sql = "select $properties from vwHREmploymentList where JobClassDescr like '%$job%' and EmploymentStatusIsActive = 1"
  Invoke-Sqlcmd @escapeDBParams -query $sql
 }
}
function Get-LFUser {
 process {
  $sql = "select * from cf_users where email = '{0}'" -f $_
  Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
  Invoke-Sqlcmd @lfFormsDBParams -Query $sql
 }
}
function Get-TeamRole {
 process {
  $team = $_.SiteDescr | Get-Team
  $user = $_.EmailWork | Get-LFUser
  if ((-not($team)) -or (-not($user))) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   Write-Warning ('{0},{1},{2},team [{3}] or user [{4}] not found' -f $msgVars)
  }
  else {
   $sql = ("select * from team_roles where (team_id = {0} and name = '{1}')" -f $team.id, $_.JobClassDescr)
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Invoke-Sqlcmd @lfFormsDBParams -query $sql
  }
 }
}
function Get-Team {
 process {
  if ($_) {
   $sql = "select * from teams where name = `'{0}`'" -f $_
   $result = Invoke-Sqlcmd @lfFormsDBParams -query $sql
   if ($result) {
    Write-Verbose ('{0},{1},Team Present' -f $MyInvocation.MyCommand.name, $_ )
    $result
   }
   else {
    Write-Warning ('{0},{1},Team NOT Present' -f $MyInvocation.MyCommand.name, $_ )
    $_
   }
  }
 }
}
function Get-TeamMember {
 process {
  $team = $_.SiteDescr | Get-Team
  $user = $_.EmailWork | Get-LFUser
  if ((-not($team)) -or (-not($user))) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   Write-Warning ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars)
  }
  else {
   $sql = ("select * from team_members where (user_id = {0} and team_id = {1})" -f $user.user_id, $team.id)
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Invoke-Sqlcmd @lfFormsDBParams -query $sql
  }
 }
}
function Get-TeamMemberRoleMapping {
 process {
  $teamRole = $_ | Get-TeamRole
  $teamMember = $_ | Get-TeamMember
  if ( -not($teamRole) -or -not($teamMember) ) {
   $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
   Write-Warning ('{0},{1},{2},Missing team_role_id [{3}] or (team_member) id [{4}]' -f $msgVars)
  }
  else {
   $sql = "select * from team_member_team_role_mapping where (team_role_id = {0} and team_member_id = {1});" -f $teamRole.id, $teamMember.id
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Invoke-Sqlcmd @lfFormsDBParams -query $sql
  }
 }
}
function Invoke-LFSql ($sql) {
 process {
  if ($WhatIf) { Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql) }
  else { Invoke-SqlCmd @lfFormsDBParams -Query $sql }
 }
}
# ======================================================================
. .\lib\Load-Module.ps1
'SqlServer' | Load-Module

$lfFormsDBParams = @{
 Server     = $LaserficheFormsInstance
 Database   = $LaserficheFormsDatabase
 Credential = $LaserficheDBCredential
}

# Escape JobClasses is where all the magic happens. Every Laserfiche Team and Role update stems from these classes.
# !!! The SQL query uses wildcards around each class, !!!
# !!! so test each class in your SQL env first before adding a new one !!!

$escUsers = $JobClasses | Get-EscapeUserByJobClass
# $escUsers

$sites = $escUsers.SiteDescr | Select-Object -Unique
# $sites | Get-Team

$sites | Add-Team
$escUsers | Add-Role
$escUsers | Add-TeamMember
$escUsers | Add-TeamMemberRoleMapping