-- ============================================================
--  THÊM CỘT KHỐI LƯỢNG (weight) VÀO BẢNG PRODUCTS
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
--
--  Lưu dạng chữ, luôn có đuôi "g" (vd "10g", "25g", "150g") để
--  trang lọc khối lượng đọc được số ra so sánh khoảng — admin
--  chọn 1 trong 4 mức có sẵn (10/25/50/100) hoặc tự nhập số cho
--  "Khác", đều tự động ghép "g" phía sau khi lưu.
-- ============================================================

alter table public.products add column if not exists weight text;
