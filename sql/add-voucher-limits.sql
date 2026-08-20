-- ============================================================
--  THÊM GIỚI HẠN SỐ LẦN DÙNG CHO vouchers
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
--  Voucher cũ đã tạo trước đây sẽ tự nhận giá trị mặc định 1
--  cho cả 2 cột — vào admin/voucher.html sửa lại nếu cần số khác.
-- ============================================================

-- Tổng số lượt tối đa CHO CẢ VOUCHER (tính chung mọi khách hàng), giống tồn kho
alter table public.vouchers add column if not exists total_quantity integer not null default 1;

-- Số lượt tối đa MỖI KHÁCH HÀNG được dùng riêng mã này
alter table public.vouchers add column if not exists max_uses_per_customer integer not null default 1;
