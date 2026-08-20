-- ============================================================
--  THÊM CỘT CHO admin/blog.html — CRUD bài viết thật
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
-- ============================================================

-- Đoạn trích ngắn hiện ở trang danh sách (admin tự viết, không cắt tự động từ content)
alter table public.blog_posts add column if not exists excerpt text;

-- SEO
alter table public.blog_posts add column if not exists meta_title text;
alter table public.blog_posts add column if not exists meta_description text;
