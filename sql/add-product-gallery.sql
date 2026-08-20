-- ============================================================
--  THÊM CỘT ẢNH PHỤ (gallery) VÀO BẢNG PRODUCTS
--  Yến Sào Yến Duyên
-- ------------------------------------------------------------
--  CÁCH DÙNG (chạy 1 lần):
--    Supabase → SQL Editor → New query → dán file này → Run.
--
--  Tác dụng: thêm cột gallery (danh sách link ảnh phụ).
--    - gallery lưu dạng mảng URL text, ví dụ:
--        {"https://...a.jpg","https://...b.jpg"}
--    - Nếu không có ảnh phụ → để NULL (trang vẫn hoạt động).
--    - Ảnh đại diện chính vẫn là cột image_url như cũ.
--    - An toàn chạy lại nhiều lần (IF NOT EXISTS).
-- ============================================================

alter table public.products
  add column if not exists gallery text[];

-- ============================================================
--  XONG.
--  Vào Supabase → Table Editor → bảng products → sẽ thấy
--  cột "gallery" mới. Để NULL cho sản phẩm cũ là đúng.
-- ============================================================
