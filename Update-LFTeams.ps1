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
 # [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
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
# Output Colors
$aware = 'Blue'
$delete = 'Red'
$get = 'Green'
$update = 'Magenta'

function Add-Role ($params, $formsDB) {
 begin {
  $insertRoleSql = Get-Content -Path '.\sql\insert-role.sql' -Raw
  $checkRoleSql = "SELECT * FROM team_roles WHERE team_id = @teamId AND name = @name AND is_deleted = 0"
 }
 process {
  $teamRole = $_ | Get-TeamRole $params
  Write-Verbose ($teamRole | out-string)
  if ($teamRole) { return } # Wait until team role entry added
  $team = $_.SiteDescr | Get-Team $params
  if (-not$team) { return } # Wait until team is added

  Write-Host ('{0},[{1}],{2}' -f $MyInvocation.MyCommand.name, $_.JobClassDescr, $team.name) -F $get
  $roleVars = "teamId=$team.id", "name=$($_.JobClassDescr)"
  if ($formsDB -match 'SANDBOX') { $insertRoleSql = $insertRoleSql.replace('SET', '--SET') }

  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $checkRoleSql) -f $get
  $checkSql = New-SqlOperation @params -Query $checkRoleSql -Parameters $roleVars
  if ($checkSql) { return }

  Write-Host ('{0}, sql: [{1}]' -f $MyInvocation.MyCommand.name, $insertRoleSql, ($sqlVars -join ',')) -F $update
  if ($WhatIf) { return }
  # Insert New team role
  New-SqlOperation @params -Query $insertRoleSql -Parameters $roleVars
 }
}

function Add-Team ($params) {
 begin {
  $sql = Get-Content -Path '.\sql\insert-team.sql' -Raw
 }
 process {
  Write-Verbose ('{0},Checking Team: [{1}]' -f $MyInvocation.MyCommand.name, $_)
  # if the input is null then create a team matching the input
  $check = $_ | Get-Team $params
  if ($check) { return (Write-Verbose ('{0},Team Found: [{1}]' -f $MyInvocation.MyCommand.name, $_)) }
  $sqlVars = "name=$($_)"
  # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
  Write-Host ('{0},Adding Team: [{1}]' -f $MyInvocation.MyCommand.name, $_) -F $update
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  if ($WhatIf) { return }
  New-SqlOperation @params -Query $sql -Parameters $sqlVars
 }
}

function Add-TeamMember ($params) {
 begin {
  $sql = Get-Content -Path '.\sql\insert-team_member.sql' -Raw
 }
 process {
  $check = $_ | Get-TeamMember $params
  $team = $_.SiteDescr | Get-Team $params
  $user = $_.EmailWork | Get-LFUser $params
  if ($check) { return }
  if ( -not($user) -or -not($team) ) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   return (Write-Verbose ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars))
  }
  $msgVars = $MyInvocation.MyCommand.name, $user.user_id, $user.username, $user.email, $user.displayname, $team.name
  Write-Host ('{0},{1},{2},{3},{4},{5}' -f $msgVars) -F $aware
  # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
  $sqlVars = "userGroupId=$($user.user_id)", "teamId=$($team.id)"
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  if ($WhatIf) { return }
  New-SqlOperation @params -Query $sql -Parameters $sqlVars
 }
}

function Add-TeamMemberRoleMapping ($params) {
 begin {
  $sql = Get-Content -Path '.\sql\insert-team_member_team_role_mapping.sql' -Raw
 }
 process {
  $teamRole = $_ | Get-TeamRole $params
  $teamMember = $_ | Get-TeamMember $params
  $check = $_ | Get-TeamMemberRoleMapping $params
  if (!$check) {
   if ( !$teamRole -or !$teamMember ) {
    $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
    return (Write-Verbose ('{0},{1},{2},Missing role [{3}] or (team_member_id) id [{4}]' -f $msgVars))
   }
   $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
   Write-Host ('{0},{1},{2},Mapping role [{3}] to (team_member_id) id [{4}]' -f $msgVars) -Fore $aware
   $sqlVars = "teamRoleId=$($teamRole.id)", "teamMemberId=$($teamMember.id)"
   Write-Host ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ',')) -F $update
   if ($WhatIf) { return }
   New-SqlOperation @params -Query $sql -Parameters $sqlVars
  }
 }
}

function Get-EscapeUserByJobClass ($params) {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_) -Fore $get
  $job = $_
  $properties = 'EmailWork,JobClassDescr,EmploymentStatusIsActive,SiteId,SiteDescr'
  $sql = "Select $properties from vwHREmploymentList where JobClassDescr like '%$job%' and EmploymentStatusIsActive = 1"
  New-SqlOperation @params -query $sql
 }
}

function Get-LFUser ($params) {
 process {
  $sql = "SELECT * FROM cf_users WHERE email = @email AND is_activated = 1; "
  $sqlVars = "email=$($_)"
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, $sqlVars)
  New-SqlOperation @params -Query $sql -Parameters $sqlVars
 }
}

function Get-TeamRole ($params) {
 process {
  $team = $_.SiteDescr | Get-Team $params
  $user = $_.EmailWork | Get-LFUser $params
  if ((-not($team)) -or (-not($user))) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   return (Write-Verbose ('{0},{1},{2},team [{3}] or user [{4}] not found' -f $msgVars))
  }
  $sql = "Select-Object * FROM team_roles WHERE (team_id = @teamId AND name = @name) AND is_deleted = 0;"
  $sqlVars = "teamId=$($team.id)", "name=$($_.JobClassDescr)"
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  New-SqlOperation @params -query $sql -Parameters $sqlVars
 }
}

function Get-Team ($params) {
 process {
  $teamName = $_
  if (!$teamName) { return }
  $sql = "Select * FROM teams WHERE name = @name AND is_deleted = 0;"
  $sqlVars = "name=$teamName"
  $result = New-SqlOperation @params -query $sql -Parameters $sqlVars
  if (!$result) { return (Write-Verbose ('{0},{1},Team NOT Present' -f $MyInvocation.MyCommand.name, $_ )) }
  Write-Verbose ('{0},{1},Team Present' -f $MyInvocation.MyCommand.name, $_ )
  $result
 }
}

function Get-TeamMember ($params) {
 process {
  $team = $_.SiteDescr | Get-Team $params
  $user = $_.EmailWork | Get-LFUser $params
  if ((-not($team)) -or (-not($user))) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   return (Write-Verbose ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars))
  }
  # Including 'AND leave_date IS NULL' to filter for active members
  $sql = "Select-Object * from team_members where (user_group_id = @userGroupId and team_id = @teamId) AND leave_date IS NULL;"
  $sqlVars = "userGroupId=$($user.user_id)", "teamId=$($team.id)"
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  New-SqlOperation @params -query $sql -Parameters $sqlVars
 }
}

function Get-TeamMemberRoleMapping ($params) {
 process {
  $teamRole = $_ | Get-TeamRole $params
  $teamMember = $_ | Get-TeamMember $params | Sort-Object -Property join_date -Descending
  if ( -not($teamRole) -or -not($teamMember) ) {
   $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
   return (Write-Verbose ('{0},{1},{2},Missing team_role_id [{3}] or (team_member) id [{4}]' -f $msgVars))
  }
  # The 'team_member_team_role_mapping' table only has 2 columns: team_member_id and team_role_id
  $sql = "Select-Object * from team_member_team_role_mapping where (team_role_id = @teamRoleId and team_member_id = @teamMemberId);"
  $sqlVars = "teamRoleId=$($teamRole.id)", "teamMemberId=$($teamMember.id)"
  Write-Verbose ('{0}, sql: [{1}],[{2}]' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  New-SqlOperation @params -query $sql -Parameters $sqlVars
 }
}
# ============================================================================================
Import-Module -Name CommonScriptFunctions, dbatools

if ($WhatIf) { Show-TestRun }
Show-BlockInfo main

$lfFormsDBParams = @{
 Server     = $LaserficheFormsInstance
 Database   = $LaserficheFormsDatabase
 Credential = $LaserficheDBCredential
}

$empDBParams = @{
 Server     = $EscapeServer
 Database   = $EscapeDatabase
 Credential = $EscapeCredential
}
# Escape JobClasses is where all the magic happens. Every Laserfiche Team and Role update stems from these classes.
# !!! The SQL query uses wildcards around each class, !!!
# !!! so test each class in your SQL env first before adding a new one !!!

$employeeData = $JobClasses | Get-EscapeUserByJobClass $empDBParams
# $employeeData

$sites = $employeeData.SiteDescr | Select-Object -Unique
# $sites | Get-Team

# $sites | Add-Team $lfFormsDBParams
# $employeeData | Add-Role $lfFormsDBParams $LaserficheFormsDatabase
# $employeeData | Add-TeamMember $lfFormsDBParams
$employeeData | Add-TeamMemberRoleMapping $lfFormsDBParams

Show-BlockInfo end
if ($WhatIf) { Show-TestRun }
