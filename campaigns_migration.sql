-- Add coupon code support to campaigns
ALTER TABLE public.campaigns
ADD COLUMN IF NOT EXISTS coupon_code text;
