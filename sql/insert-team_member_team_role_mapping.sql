-- insert-team_member_team_role_mapping.sql
INSERT INTO team_member_team_role_mapping
( team_role_id,team_member_id )
VALUES
( @teamRoleId,@teamMemberId);