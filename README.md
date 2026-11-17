# Identity Security Metrics That Matter (Okta + Databricks Lab)

An end-to-end identity security analytics lab: generate real identity activity in Okta, model the System Log in Databricks, and turn it into a small set of metrics that a security leader can act on.



## Why this project

Identity platforms produce thousands of log events, but leadership needs a handful of numbers that answer: *Are we protected? Where is the risk? What should we do next?* This lab builds that path from raw Okta events to "metrics that matter" and a written recommendation.

## Architecture

```
Okta (trial tenant)          Databricks (Free Edition)                         Output
-------------------          -----------------------------------------         --------------------
Users, groups, apps    -->   okta_system_log      (raw, 508 events)       -->  AI/BI dashboard with
MFA policy by group          identity_events      (cleaned, 105 events)        findings and
System Log CSV export        user_directory       (HR status stand-in)         recommendations
                             metric queries       (5 metrics)
```

## What I built

**1. Okta tenant**
- 9 test users across 3 groups (Finance, IT, Operations) plus an admin account
- 3 bookmark apps, each assigned to one group
- Group-based authentication policy: IT requires two factors (Google Authenticator); Finance and Operations are password-only. This was set up on purpose to create a measurable MFA gap.
- Generated realistic activity: sign-ins, failed passwords, MFA enrollment, password changes, app launches (SSO), an admin role grant, and a deactivated leaver. One account was intentionally left unused.

**2. Databricks pipeline**
- Loaded the Okta System Log export as a raw table
- Built a cleaned `identity_events` table limited to end-user identity events, with readable column names
- Added a `user_directory` table that stands in for an HR source of truth (department and employment status)
- SQL is in [`sql/identity_metrics.sql`](sql/identity_metrics.sql)

**3. Dashboard**
- Five metrics, each with a one-line takeaway, plus an overall summary and recommendations

## Metrics

| Metric | Definition | Why it matters |
|---|---|---|
| MFA adoption by department | Users with an enrolled MFA authenticator ÷ total users, per department | Accounts without MFA are the easiest to take over |
| Authentication failure rate | Failed `user.session.start` events ÷ all sign-in attempts, per department | Spikes can signal password spraying or credential stuffing |
| Dormant accounts | Active accounts with no successful sign-in | Unused accounts are attack surface no one is watching |
| Privileged access grants | Admin role grants, with who granted them and when | Privileged access should be small, known, and reviewed |
| Leaver deprovisioning | Terminated users (per HR) checked against Okta deactivation | Orphaned accounts are a common audit finding |

## Findings (lab data)

- MFA adoption is **33% org-wide**: IT 100%, Finance 0%, Operations 0%.
- **7 of 8 failed sign-ins** came from the password-only groups (Operations 67% failure rate, Finance 50%, IT 20%).
- **1 dormant account** (active, never signed in).
- **2 privileged grants**, both logged with the granting admin.
- **Leaver check passed:** the terminated user was deactivated in Okta; no orphaned accounts.

**Recommendations:** extend MFA to Finance and Operations, review and deactivate the dormant account, and review privileged access quarterly.

## Data quality notes

Details I had to handle to make the numbers trustworthy:

- **Double-counted failures.** In Okta Identity Engine, a failed password appears as both `user.session.start` and `user.authentication.auth_via_mfa`. Counting both doubles the failure count (16 instead of 8), so failure metrics use `user.session.start` only.
- **Misleading MFA events.** `user.mfa.factor.activate` also fires when an admin sets a password. True MFA adoption counts only rows where the enrolled authenticator is an MFA factor (here, Google Authenticator).
- **Admin noise.** About half of the raw log was setup activity (policy changes, OAuth tokens, app configuration). The cleaned table filters to end-user identity events.

## Limitations

- This is a small lab tenant (10 users, one evening of activity), so the percentages show the method, not real-world rates.
- All activity came from one laptop, so every event shares one IP address.
- `user_directory` is a hand-built stand-in for an HR feed.

## Next steps

- **Anomaly detection:** add a larger synthetic sign-in dataset and train an Isolation Forest model on sign-in features (time of day, new device, failed attempts before success) to flag suspicious logins.
- **Data quality scoring:** automated checks for null user IDs, duplicate events, and accounts with no HR match.
- **Executive brief:** a one-page summary of the three headline metrics, one trend, one risk, and one recommendation.

## Tools

Okta Workforce Identity (trial) · Okta System Log · Databricks Free Edition · Databricks SQL · Databricks AI/BI Dashboards
