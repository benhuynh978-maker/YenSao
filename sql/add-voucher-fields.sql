-- ============================================================
--  THÊM CỘT MỚI CHO BẢNG vouchers — Ngày bắt đầu + Áp dụng cho
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
-- ============================================================

-- Ngày bắt đầu áp dụng (để trống = áp dụng ngay)
alter table public.vouchers add column if not exists start_date timestamptz;

-- Áp dụng cho: 'all' | 'new_customer' | 'vip' | 'products'
-- ('new_customer' và 'vip' hiện chỉ là nhãn lưu trước, chưa có logic kiểm tra
--  thật lúc khách áp mã ở giỏ hàng — sẽ làm ở task riêng sau)
alter table public.vouchers add column if not exists apply_scope text not null default 'all';

-- Danh sách ID sản phẩm được áp dụng, chỉ dùng khi apply_scope = 'products'
alter table public.vouchers add column if not exists apply_product_ids uuid[] default '{}';
