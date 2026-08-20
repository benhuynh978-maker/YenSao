-- ============================================================
--  GẮN ĐÁNH GIÁ VỚI ĐƠN HÀNG THẬT (order_id + user_id)
--  + CHẶN TỰ ĐĂNG REVIEW "ĐÃ DUYỆT" (vá lỗ P1-2)  — FILE CHUẨN
-- ------------------------------------------------------------
--  ĐÂY LÀ FILE DUY NHẤT định nghĩa policy reviews_insert (bản đầy đủ).
--  Thay thế hẳn sql/fix-review-self-publish.sql (đã xoá) — đừng tạo
--  thêm file nào khác cũng drop/create reviews_insert nữa, tránh
--  "đá nhau" như lỗi đã gặp (14/07/2026).
--
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (nullable) + policy, không đụng dữ liệu cũ.
--  Review cũ (ẩn danh, order_id/user_id trống) vẫn hoạt động bình thường.
--
--  Chạy file này xong: (a) bật được tính năng "đánh giá sản phẩm trong
--  đơn đã giao" ở don-hang-cua-toi.html, VÀ (b) đóng lỗ P1-2 (người
--  thường không tự đặt is_published=true được).
--  Xem CLAUDE.md mục "Kiến trúc bảo mật".
-- ============================================================

-- 1) Thêm 2 cột (nếu chưa có) — nguồn "column does not exist" trước đây.
--    LƯU Ý: orders.id trên DB thật là kiểu BIGINT (số), KHÔNG phải uuid như
--    SETUP-DATABASE.sql ghi → order_id phải là bigint mới tạo được khóa ngoại.
--    (user_id là uuid vì auth.users.id là uuid.)
alter table public.reviews add column if not exists order_id bigint references public.orders(id) on delete set null;
alter table public.reviews add column if not exists user_id uuid references auth.users(id) on delete set null;

-- 2) Policy insert AN TOÀN.
--    QUAN TRỌNG: KHÔNG tham chiếu bảng public.orders trong policy này. Vì P0-1 đã
--    revoke quyền đọc orders của anon, mà đánh giá ở trang sản phẩm là ẩn danh
--    (không đăng nhập) → nếu policy phải đọc orders sẽ báo "permission denied for
--    table orders" và CHẶN LUÔN đánh giá công khai (lỗi hồi quy đã gặp 14/07/2026).
--    Quy tắc đủ cho P1-2:
--    - CHỐNG tự-publish: người KHÔNG phải admin buộc is_published=false (chờ duyệt).
--    - Toàn vẹn danh tính: nếu có gắn user_id thì phải khớp chính mình (không gán
--      review đứng tên người khác). order_id chỉ là metadata (đơn nào), không kiểm ở đây.
drop policy if exists reviews_insert on public.reviews;
create policy reviews_insert on public.reviews
  for insert with check (
    public.is_admin()
    or (
      is_published = false
      and (user_id is null or user_id = auth.uid())
    )
  );

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    - Ẩn danh/khách chèn review is_published=true → PHẢI bị từ chối (RLS 42501).
--    - Form đánh giá (is_published=false) ở trang sản phẩm → vẫn OK, chờ duyệt.
--    - Đánh giá sản phẩm trong đơn 'delivered' của mình → OK, không còn lỗi
--      "column order_id does not exist".
-- ============================================================
