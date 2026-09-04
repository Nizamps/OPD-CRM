# OPD Campaign CRM — Live Google Sheets

This version is designed for a GitHub Pages frontend + Supabase + Google Apps Script live sync worker.

## What you get

- Admin connects a Google Sheet by pasting its URL.
- Choose the lead source (Meta / WhatsApp CTA / RCS / Hospital Dump / Other).
- Choose the campaign.
- The CRM stores the connection in Supabase.
- Google Apps Script checks active connections every minute and imports new appended rows.
- New leads are automatically assigned round-robin to active caller profiles by a database function.
- Duplicate phone numbers are skipped within the same campaign.
- Callers only see leads assigned to them through Supabase RLS.

Supabase Edge Functions/Cron are not required for this first live-sync version. Supabase officially supports secrets for server-side functions, while Google Apps Script can open spreadsheets by URL using the account that authorized the script. For this workflow, Apps Script is used as the Google-side connector and Supabase remains the CRM database. Google Sheets can be kept private to the Google account running the script.

## 1. Supabase

Run the entire `schema.sql` in Supabase SQL Editor.

Create your users under Authentication → Users. The profile trigger creates `public.profiles`.
Promote the admin profile:

```sql
update public.profiles
set full_name='Your Name', role='admin', is_active=true
where id='YOUR_AUTH_USER_UUID';
```

Create three callers as Auth users and ensure their profiles have `role='caller'`.

## 2. Google Apps Script connector

Open https://script.google.com and create a new standalone project.
Paste `Code.gs` into the editor.

Open **Project Settings → Script Properties** and add:

- `SUPABASE_URL` = `https://YOUR_PROJECT.supabase.co`
- `SUPABASE_SECRET_KEY` = your NEW rotated Supabase secret key
- `WEBHOOK_TOKEN` = a long random string (optional)

The secret key is server-side only. Do not put it in GitHub or `index.html`.

Run `setupTrigger()` once from the Apps Script editor and approve the requested Google permissions. This creates the periodic sync trigger.

Deploy the script as a Web App:

- Execute as: Me
- Who has access: Anyone

Copy the deployed Web App URL.

## 3. GitHub frontend

Open `index.html` and set the Supabase config near the top of the script:

```js
window.SUPABASE_CONFIG = {
  url: 'https://YOUR_PROJECT.supabase.co',
  anonKey: 'YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY',
  googleSyncUrl: 'YOUR_APPS_SCRIPT_WEB_APP_URL'
};
```

Use only a Publishable/Anon key in the browser. Never use `sb_secret_...` or a service-role key in `index.html`.

Upload these files directly to the root of your GitHub repository:

- `index.html`
- `schema.sql`
- `Code.gs`
- `README.md`

## 4. Connect your live sheets

In the CRM as Admin:

**Google Sheets → + Connect Google Sheet**

Enter:

- Connection name
- Google Sheet URL
- Sheet tab name
- Lead Source
- Campaign
- Optional patient name header
- Optional phone header

Row 1 must be the header row. New Meta/RCS/WhatsApp/etc. leads should be appended below it.

The sync worker uses common aliases such as `name`, `patient_name`, `full name`, `phone`, `mobile`, `phone number`, etc. If your header is unusual, specify it in the connection form.

## 5. How assignment works

All active caller profiles are ordered by creation time. A database lock protects the assignment pointer. Each new lead gets the next caller in round-robin order.

Example:

Caller 1 → Caller 2 → Caller 3 → Caller 1 → Caller 2 → ...

If a phone number already exists in the same campaign, the incoming row is skipped as a duplicate.

## 6. Important operational note

The first version is optimized for lead streams that append new rows at the bottom of a sheet. It intentionally does not overwrite calling/OPD status from the CRM when an old source row changes.

## 7. After this is running

Recommended upgrades:

- source-specific column mapping presets for each Meta/RCS/WhatsApp sheet
- automatic campaign creation for each weekend
- connection pause/resume
- sync health page and error logs
- source-to-campaign rules
- bulk reassignment
- CSV/XLSX export
- daily team report
- direct Meta/WhatsApp/RCS webhooks where available
