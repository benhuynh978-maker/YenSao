-- ============================================================
--  THÊM CỘT payment_method VÀO orders
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (nullable), không đụng dữ liệu cũ.
--  Lý do: dat-hang.html đã tính phương thức thanh toán (cod/transfer)
--  từ lâu nhưng cột này chưa từng được tạo trong Supabase — khiến
--  insert đơn hàng bị Supabase từ chối khi payload gửi kèm field
--  không tồn tại trong bảng.
-- ============================================================

alter table public.orders add column if not exists payment_method text;
