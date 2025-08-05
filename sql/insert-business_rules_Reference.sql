-- jcooper user_id is 45 and jcooper Created_by_snapshot_id 49.
-- We need to turn identity_insert to on,
-- and then off again when the operation is complete

SET IDENTITY_INSERT business_rules ON;


insert into business_rules
(
 id
 ,label
 ,script
 ,team_id
)
values 
(
 ((select max(id) from business_rules) + 1)
 ,{0}
 ,{1}
 ,{2}
);

SET IDENTITY_INSERT business_rules OFF;