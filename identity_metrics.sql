-- Identity Security Metrics That Matter
-- Okta System Log -> Databricks SQL
-- Raw table: workspace.default.okta_system_log (Okta System Log CSV export)
-- Note: the CSV keeps dotted column names, so they must be wrapped in backticks.

-- =========================================================
-- 1. Cleaned events table (end-user identity events only)
-- =========================================================
CREATE OR REPLACE TABLE workspace.default.identity_events AS
SELECT
  uuid                                AS event_id,
  `timestamp`                         AS event_time,
  event_type,
  display_message,
  `outcome.result`                    AS outcome,
  `outcome.reason`                    AS outcome_reason,
  `actor.display_name`                AS actor_name,
  `actor.alternate_id`                AS actor_username,
  `client.ip_address`                 AS ip_address,
  `client.geographical_context.city`  AS city,
  `client.user_agent.browser`         AS browser,
  `target0.display_name`              AS target_name,
  `target1.display_name`              AS target_detail
FROM workspace.default.okta_system_log
WHERE event_type IN (
  'user.session.start', 'user.session.end', 'user.authentication.sso',
  'user.mfa.factor.activate', 'user.account.update_password',
  'user.lifecycle.create', 'user.lifecycle.activate', 'user.lifecycle.deactivate',
  'user.account.privilege.grant'
);

-- =========================================================
-- 2. User directory (stand-in for an HR source of truth)
-- =========================================================
CREATE OR REPLACE TABLE workspace.default.user_directory AS
SELECT * FROM VALUES
  ('Jordan Lee',    'Finance',    'active'),
  ('Maria Gomez',   'Finance',    'active'),
  ('Sam Patel',     'Finance',    'active'),
  ('Alex Kim',      'IT',         'active'),
  ('Taylor Brooks', 'IT',         'active'),
  ('Chris Nguyen',  'IT',         'active'),
  ('Dana White',    'Operations', 'active'),
  ('Riley Adams',   'Operations', 'terminated'),
  ('Morgan Shaw',   'Operations', 'active')
AS t(user_name, department, hr_status);

-- =========================================================
-- Metric 1: MFA adoption by department
-- Counts only real MFA enrollments (admin-set passwords also
-- emit user.mfa.factor.activate, so filter on the authenticator).
-- =========================================================
SELECT
  d.department,
  COUNT(*)                                        AS users,
  COUNT(m.user_name)                              AS mfa_enrolled,
  ROUND(100 * COUNT(m.user_name) / COUNT(*), 0)   AS mfa_adoption_pct
FROM workspace.default.user_directory d
LEFT JOIN (
  SELECT DISTINCT target_name AS user_name
  FROM workspace.default.identity_events
  WHERE event_type = 'user.mfa.factor.activate'
    AND target_detail = 'Google Authenticator'
) m ON d.user_name = m.user_name
GROUP BY d.department
ORDER BY mfa_adoption_pct;

-- =========================================================
-- Metric 2: Authentication failure rate by department
-- Uses user.session.start only; Okta also logs each failed
-- password as user.authentication.auth_via_mfa (double count).
-- =========================================================
SELECT
  d.department,
  COUNT(*)                                                   AS sign_in_attempts,
  COUNT_IF(e.outcome = 'FAILURE')                            AS failures,
  ROUND(100 * COUNT_IF(e.outcome = 'FAILURE') / COUNT(*), 1) AS failure_rate_pct
FROM workspace.default.identity_events e
JOIN workspace.default.user_directory d ON e.actor_name = d.user_name
WHERE e.event_type = 'user.session.start'
GROUP BY d.department
ORDER BY failure_rate_pct DESC;

-- =========================================================
-- Metric 3: Dormant accounts (active, never signed in)
-- =========================================================
SELECT d.user_name, d.department
FROM workspace.default.user_directory d
WHERE d.hr_status = 'active'
  AND d.user_name NOT IN (
    SELECT actor_name FROM workspace.default.identity_events
    WHERE event_type = 'user.session.start' AND outcome = 'SUCCESS'
  );

-- =========================================================
-- Metric 4: Privileged access grants
-- =========================================================
SELECT event_time, actor_name AS granted_by, target_name AS granted_to
FROM workspace.default.identity_events
WHERE event_type = 'user.account.privilege.grant'
ORDER BY event_time;

-- =========================================================
-- Metric 5: Leaver deprovisioning (HR status vs. Okta)
-- =========================================================
SELECT
  d.user_name,
  d.hr_status,
  MAX(CASE WHEN e.event_type = 'user.lifecycle.deactivate' THEN e.event_time END) AS okta_deactivated_at,
  CASE WHEN MAX(CASE WHEN e.event_type = 'user.lifecycle.deactivate' THEN 1 END) = 1
       THEN 'Deprovisioned' ELSE 'ORPHANED - still active' END AS status
FROM workspace.default.user_directory d
LEFT JOIN workspace.default.identity_events e ON d.user_name = e.target_name
WHERE d.hr_status = 'terminated'
GROUP BY d.user_name, d.hr_status;
