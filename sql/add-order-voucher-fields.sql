-- ============================================================
--  THÊM CỘT VOUCHER VÀO orders — để lưu mã đã dùng + số tiền giảm
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
-- ============================================================

alter table public.orders add column if not exists voucher_code text;
alter table public.orders add column if not exists discount_amount bigint default 0;
