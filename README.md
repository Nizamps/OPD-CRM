# OPD Campaign CRM

## GitHub upload
Upload these files directly to the root of your GitHub repository:

- `index.html` — complete frontend; CSS and JavaScript are already embedded.
- `schema.sql` — Supabase database schema and RLS policies.
- `README.md` — setup notes.

## Supabase
1. Run `schema.sql` in Supabase SQL Editor.
2. Create users in Supabase Authentication.
3. Promote your admin profile using the SQL at the bottom of `schema.sql`.
4. Open `index.html` and replace `PASTE_YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY_HERE` with your Supabase Publishable/Anon key. Never put a `sb_secret` or service-role key in the site.

## GitHub Pages
Enable GitHub Pages and deploy the repository root.

## Current build
Dashboard, campaigns, leads, caller permissions, lead import, round-robin assignment, calling status, OPD status, follow-up fields, call history, and filtered CSV export.
