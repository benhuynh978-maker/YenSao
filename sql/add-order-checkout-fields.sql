-- ============================================================
--  THÊM CỘT EMAIL + PHÍ SHIP VÀO orders
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
-- ============================================================

-- Email khách nhập lúc đặt hàng (trước đây có ô nhập nhưng không lưu)
alter table public.orders add column if not exists customer_email text;

-- Phí vận chuyển đã tính vào đơn (0 nếu đủ điều kiện miễn phí)
alter table public.orders add column if not exists shipping_fee bigint not null default 0;
