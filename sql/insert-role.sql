-- insert-role.sql
-- if some_user_id is 45 and some_user Created_by_snapshot_id 49.
-- We need to turn identity_insert to on,
-- and then off again when the operation is complete

SET IDENTITY_INSERT team_roles ON;

INSERT INTO team_roles
(
 id
 ,team_id
 ,name
 ,description
 ,is_deleted
 ,date_updated
 ,updated_by_snapshotid
)
VALUES
(
 ((SELECT MAX(id) FROM team_roles) + 1)
 ,@teamId
 ,@name
 ,@name
 ,0
 ,CURRENT_TIMESTAMP
 ,49
);

SET IDENTITY_INSERT team_roles OFF;