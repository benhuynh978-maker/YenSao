-- ============================================================
--  THÊM THÔNG TIN VẬN CHUYỂN VÀO orders
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (nullable), không đụng dữ liệu cũ.
-- ============================================================

alter table public.orders add column if not exists shipping_provider text;
alter table public.orders add column if not exists shipping_code text;
