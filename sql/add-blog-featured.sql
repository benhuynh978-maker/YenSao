-- ============================================================
--  THÊM CỘT "BÀI NỔI BẬT" CHO admin/blog.html
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
-- ============================================================

-- Admin bật/tắt để bài viết xuất hiện trong carousel "Bài nổi bật"
-- ở đầu trang khoi-nghiep.html (mặc định tắt cho bài mới)
alter table public.blog_posts add column if not exists is_featured boolean not null default false;
