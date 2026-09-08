-- Allow Admins and Callers to add leads manually from the CRM.
-- Callers are automatically assigned to themselves; Admins may choose a caller.

create or replace function public.add_lead_manual(
  p_patient_name text,
  p_phone text,
  p_source_id uuid,
  p_campaign_id uuid,
  p_assigned_to uuid default null,
  p_calling_status public.calling_status default 'not_called',
  p_opd_status public.opd_status default 'not_discussed',
  p_follow_up_date date default null,
  p_follow_up_time time default null,
  p_remarks text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_phone text := right(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'),10);
  v_existing uuid;
  v_assigned uuid;
  v_lead uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles
    where id=auth.uid() and is_active=true and role in ('admin','caller')
  ) then
    raise exception 'Only active CRM users can add leads';
  end if;

  if coalesce(trim(p_patient_name),'')='' then
    raise exception 'Patient name is required';
  end if;

  if v_phone='' then
    raise exception 'Valid phone number is required';
  end if;

  if p_source_id is null or not exists(select 1 from public.lead_sources where id=p_source_id and is_active=true) then
    raise exception 'Valid lead source is required';
  end if;

  if p_campaign_id is null or not exists(select 1 from public.campaigns where id=p_campaign_id) then
    raise exception 'Valid campaign is required';
  end if;

  select id into v_existing
  from public.leads
  where campaign_id=p_campaign_id and normalized_phone=v_phone
  limit 1;

  if v_existing is not null then
    return jsonb_build_object('inserted',false,'duplicate',true,'lead_id',v_existing);
  end if;

  if public.is_admin() then
    v_assigned := p_assigned_to;
    if v_assigned is not null and not exists(
      select 1 from public.profiles where id=v_assigned and role='caller' and is_active=true
    ) then
      raise exception 'Selected caller is not active';
    end if;
  else
    v_assigned := auth.uid();
  end if;

  insert into public.leads(
    patient_name, phone, source_id, campaign_id, assigned_to,
    calling_status, opd_status, follow_up_date, follow_up_time, remarks
  ) values (
    trim(p_patient_name), trim(p_phone), p_source_id, p_campaign_id, v_assigned,
    p_calling_status, p_opd_status, p_follow_up_date, p_follow_up_time, p_remarks
  ) returning id into v_lead;

  if v_assigned is not null then
    insert into public.lead_assignments(lead_id,assigned_to,assigned_by)
    values(v_lead,v_assigned,auth.uid());
  end if;

  return jsonb_build_object('inserted',true,'duplicate',false,'lead_id',v_lead,'assigned_to',v_assigned);
exception
  when unique_violation then
    select id into v_existing from public.leads where campaign_id=p_campaign_id and normalized_phone=v_phone limit 1;
    return jsonb_build_object('inserted',false,'duplicate',true,'lead_id',v_existing);
end;
$$;

revoke all on function public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text) from public;
revoke all on function public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text) from anon;
revoke all on function public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text) from authenticated;
grant execute on function public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text) to authenticated;
