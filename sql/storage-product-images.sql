-- ============================================================
--  KHO ẢNH SẢN PHẨM (Supabase Storage) — Yến Sào Yến Duyên
-- ------------------------------------------------------------
--  CÁCH DÙNG (chạy 1 lần):
--    Supabase → SQL Editor → New query → dán file này → Run.
--
--  Tác dụng: tạo kho 'product-images' để chứa ảnh sản phẩm.
--    - Ảnh chỉ được TẢI LÊN khi bạn bấm "Lưu sản phẩm"
--      (web tự upload, bạn không phải làm gì thêm ở đây).
--    - Ai cũng XEM được ảnh (kho công khai) → web hiển thị được.
--    - Chỉ ADMIN được tải lên / sửa / xóa ảnh.
--
--  An toàn chạy lại nhiều lần.
--  (Dùng hàm is_admin() đã tạo ở file schema-yenduyen.sql)
-- ============================================================

-- 1) Tạo kho ảnh, đặt ở chế độ công khai (public)
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

-- 2) Cho phép MỌI NGƯỜI xem ảnh trong kho này
drop policy if exists product_images_read on storage.objects;
create policy product_images_read on storage.objects
  for select
  using (bucket_id = 'product-images');

-- 3) Chỉ ADMIN được TẢI LÊN / SỬA / XÓA ảnh trong kho này
drop policy if exists product_images_admin on storage.objects;
create policy product_images_admin on storage.objects
  for all
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());

-- ============================================================
--  XONG. Vào Supabase → Storage sẽ thấy kho "product-images".
--  Lúc này kho trống — ảnh sẽ tự vào đây khi bạn lưu sản phẩm.
-- ============================================================
