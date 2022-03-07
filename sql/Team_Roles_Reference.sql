/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP (1000)
      u.username
	  ,t.name
	  ,tm.[user_id]
      ,tm.[team_id]
      ,tm.[member_rights]
      ,tm.[join_date]
      ,tm.[id]
      ,tm.[leave_date]
      ,tm.[admin_rights]
      ,tm.[updated_by_snapshotid]
      ,tm.[date_updated]
  FROM [LF-FORMS].[dbo].[team_members] tm
  LEFT JOIN cf_users u
  ON tm.user_id = u.user_id
  LEFT JOIN teams t
  ON tm.team_id = t.id

ORDER BY tm.user_id