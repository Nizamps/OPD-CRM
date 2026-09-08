-- Update manual lead creation to support Hospital and Coupon Code.
-- Callers are still automatically assigned to themselves.
-- Admins can select a caller.

CREATE OR REPLACE FUNCTION public.add_lead_manual(
  p_patient_name text,
  p_phone text,
  p_source_id uuid,
  p_campaign_id uuid,
  p_assigned_to uuid DEFAULT NULL,
  p_calling_status public.calling_status DEFAULT 'not_called',
  p_opd_status public.opd_status DEFAULT 'not_discussed',
  p_follow_up_date date DEFAULT NULL,
  p_follow_up_time time DEFAULT NULL,
  p_remarks text DEFAULT NULL,
  p_hospital text DEFAULT NULL,
  p_coupon_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_phone text := right(regexp_replace(coalesce(p_phone,''),'[^0-9]','','g'),10);
  v_existing uuid;
  v_assigned uuid;
  v_lead uuid;
  v_hospital text := NULLIF(trim(p_hospital), '');
  v_coupon_code text := NULLIF(trim(p_coupon_code), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id=auth.uid() AND is_active=true AND role IN ('admin','caller')
  ) THEN
    RAISE EXCEPTION 'Only active CRM users can add leads';
  END IF;

  IF coalesce(trim(p_patient_name),'')='' THEN
    RAISE EXCEPTION 'Patient name is required';
  END IF;

  IF v_phone='' THEN
    RAISE EXCEPTION 'Valid phone number is required';
  END IF;

  IF p_source_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.lead_sources WHERE id=p_source_id AND is_active=true
  ) THEN
    RAISE EXCEPTION 'Valid lead source is required';
  END IF;

  IF p_campaign_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.campaigns WHERE id=p_campaign_id
  ) THEN
    RAISE EXCEPTION 'Valid campaign is required';
  END IF;

  IF v_hospital IS NOT NULL AND v_hospital NOT IN ('EHRC','Altius') THEN
    RAISE EXCEPTION 'Hospital must be EHRC or Altius';
  END IF;

  SELECT id INTO v_existing
  FROM public.leads
  WHERE campaign_id=p_campaign_id AND normalized_phone=v_phone
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object('inserted',false,'duplicate',true,'lead_id',v_existing);
  END IF;

  IF public.is_admin() THEN
    v_assigned := p_assigned_to;
    IF v_assigned IS NOT NULL AND NOT EXISTS(
      SELECT 1 FROM public.profiles
      WHERE id=v_assigned AND role='caller' AND is_active=true
    ) THEN
      RAISE EXCEPTION 'Selected caller is not active';
    END IF;
  ELSE
    v_assigned := auth.uid();
  END IF;

  INSERT INTO public.leads(
    patient_name, phone, source_id, campaign_id, assigned_to,
    calling_status, opd_status, follow_up_date, follow_up_time, remarks,
    hospital, coupon_code
  ) VALUES (
    trim(p_patient_name), trim(p_phone), p_source_id, p_campaign_id, v_assigned,
    p_calling_status, p_opd_status, p_follow_up_date, p_follow_up_time, p_remarks,
    v_hospital, v_coupon_code
  ) RETURNING id INTO v_lead;

  IF v_assigned IS NOT NULL THEN
    INSERT INTO public.lead_assignments(lead_id,assigned_to,assigned_by)
    VALUES(v_lead,v_assigned,auth.uid());
  END IF;

  RETURN jsonb_build_object(
    'inserted',true,
    'duplicate',false,
    'lead_id',v_lead,
    'assigned_to',v_assigned
  );
EXCEPTION
  WHEN unique_violation THEN
    SELECT id INTO v_existing
    FROM public.leads
    WHERE campaign_id=p_campaign_id AND normalized_phone=v_phone
    LIMIT 1;
    RETURN jsonb_build_object('inserted',false,'duplicate',true,'lead_id',v_existing);
END;
$$;

REVOKE ALL ON FUNCTION public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_lead_manual(text, text, uuid, uuid, uuid, public.calling_status, public.opd_status, date, time, text, text, text) TO authenticated;
