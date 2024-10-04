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

function Add-Role {
 begin {
  $insertRoleTemplate = Get-Content -Path .\sql\insert-role.txt -Raw
  $checkTeamRoleTableBase = "SELECT * FROM team_roles WHERE team_id = {0} AND name = '{1}' AND is_deleted = 0"
 }
 process {
  $teamRole = $_ | Get-TeamRole
  Write-Verbose ($teamRole | out-string)
  if ($teamRole) { return } # Wait until team role entry added
  $team = $_.SiteDescr | Get-Team
  if (-not$team) { return } # Wait until team is added

  Write-Host ('{0},[{1}],{2}' -f $MyInvocation.MyCommand.name, $_.JobClassDescr, $team.name) -F $get
  $sql = $insertRoleTemplate -f $team.id, $_.JobClassDescr
  if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }

  $checkTeamRoleSql = $checkTeamRoleTableBase -f $team.id, $_.JobClassDescr
  Write-Host ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $checkTeamRoleSql) -f $get
  $checkSql = Invoke-Sqlcmd @lfFormsDBParams -Query $checkTeamRoleSql
  if ($checkSql) { return }

  Write-Host ('{0}, sql: [{1}]' -f $MyInvocation.MyCommand.name, $sql) -F $update
  if ($WhatIf) { return }
  # Insert New team role
  Invoke-Sqlcmd @lfFormsDBParams -Query $sql
 }
}

function Add-Team {
 begin {
  $insertTeamTemplate = Get-Content -Path .\sql\insert-team.txt -Raw
 }
 process {
  Write-Verbose ('{0},Checking Team: [{1}]' -f $MyInvocation.MyCommand.name, $_)
  # if the input is null then create a team matching the input
  $check = $_ | Get-Team
  if ($check) {
   Write-Verbose ('{0},Team Found: [{1}]' -f $MyInvocation.MyCommand.name, $_)
   return
  }
  $sql = $insertTeamTemplate -f $_
  # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
  Write-Host ('{0},Adding Team: [{1}]' -f $MyInvocation.MyCommand.name, $_) -F $update
  Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
  if ($WhatIf) { return }
  Invoke-Sqlcmd @lfFormsDBParams -Query $sql
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
  if ($check) { return }
  if ( -not($user) -or -not($team) ) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   Write-Verbose ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars)
   return
  }
  $msgVars = $MyInvocation.MyCommand.name, $user.user_id, $user.username, $user.email, $user.displayname, $team.name
  Write-Host ('{0},{1},{2},{3},{4},{5}' -f $msgVars) -F $aware
  $sql = $insertTeamMemberTemplate -f $user.user_id, $team.id
  # if ($LaserficheFormsDatabase -match 'SANDBOX') { $sql = $sql.replace('SET', '--SET') }
  Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
  Write-Debug $MyInvocation.MyCommand.Name
  if ($WhatIf) { return }
  Invoke-Sqlcmd @lfFormsDBParams -Query $sql
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
    Write-Verbose ('{0},{1},{2},Missing role [{3}] or (team_member_id) id [{4}]' -f $msgVars)
   }
   else {
    $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
    Write-Host ('{0},{1},{2},Mapping role [{3}] to (team_member_id) id [{4}]' -f $msgVars) -Fore $aware
    $sql = $insertTeamRoleMappingTemplate -f $teamRole.id, $teamMember.id
    Write-Host ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql) -F $update
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
   Server                 = $EscapeServer
   Database               = $EscapeDatabase
   Credential             = $EscapeCredential
   TrustServerCertificate = $true
  }
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_) -Fore $get
  $job = $_
  $properties = 'EmailWork,JobClassDescr,EmploymentStatusIsActive,SiteId,SiteDescr'
  $sql = "select $properties from vwHREmploymentList where JobClassDescr like '%$job%' and EmploymentStatusIsActive = 1"
  Invoke-Sqlcmd @escapeDBParams -query $sql
 }
}

function Get-LFUser {
 process {
  $sql = "SELECT * FROM cf_users WHERE email = '{0}' AND is_activated = 1;" -f $_
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
   Write-Verbose ('{0},{1},{2},team [{3}] or user [{4}] not found' -f $msgVars)
  }
  else {
   $sql = ("SELECT * FROM team_roles WHERE (team_id = {0} AND name = '{1}') AND is_deleted = 0;" -f $team.id, $_.JobClassDescr)
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Invoke-Sqlcmd @lfFormsDBParams -query $sql
  }
 }
}

function Get-Team {
 process {
  if (-not$_) { return }
  $sql = "SELECT * FROM teams WHERE name = '{0}' AND is_deleted = 0;" -f $_
  $result = Invoke-Sqlcmd @lfFormsDBParams -query $sql
  if (-not$result) {
   Write-Verbose ('{0},{1},Team NOT Present' -f $MyInvocation.MyCommand.name, $_ )
   return
  }
  Write-Verbose ('{0},{1},Team Present' -f $MyInvocation.MyCommand.name, $_ )
  $result
 }
}

function Get-TeamMember {
 process {
  $team = $_.SiteDescr | Get-Team
  $user = $_.EmailWork | Get-LFUser
  if ((-not($team)) -or (-not($user))) {
   $msgVars = $MyInvocation.MyCommand.name, $_.SiteDescr, $_.EmailWork, $team.name, $user.email
   Write-Verbose ('{0},{1},{2},Team [{3}] or user [{4}] not found' -f $msgVars)
  }
  else {
   # Consider including 'AND leave_date IS NULL' to filter for active members
   $sql = ("select * from team_members where (user_group_id = {0} and team_id = {1}) AND leave_date IS NULL;" -f $user.user_id, $team.id)
   Write-Verbose ('{0}, sql: {1}' -f $MyInvocation.MyCommand.name, $sql)
   Invoke-Sqlcmd @lfFormsDBParams -query $sql
  }
 }
}

function Get-TeamMemberRoleMapping {
 process {
  $teamRole = $_ | Get-TeamRole
  $teamMember = $_ | Get-TeamMember | Sort-Object -Property join_date -Descending
  if ( -not($teamRole) -or -not($teamMember) ) {
   $msgVars = $MyInvocation.MyCommand.name, $_.JobClassDescr, $_.EmailWork, $teamRole.id, $teamMember.id
   Write-Verbose ('{0},{1},{2},Missing team_role_id [{3}] or (team_member) id [{4}]' -f $msgVars)
  }
  else {
   # The 'team_member_team_role_mapping' table only has 2 columns: team_member_id and team_role_id
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

. .\lib\Show-TestRun.ps1
. .\lib\Load-Module.ps1
'SqlServer' | Load-Module

Show-TestRun

$lfFormsDBParams = @{
 Server                 = $LaserficheFormsInstance
 Database               = $LaserficheFormsDatabase
 Credential             = $LaserficheDBCredential
 TrustServerCertificate = $true
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

Show-TestRun