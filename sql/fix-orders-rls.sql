-- ============================================================
--  ⚠️ FILE CŨ — ĐÃ BỊ THAY THẾ BỞI sql/fix-orders-rls-v2.sql. ĐỪNG CHẠY FILE NÀY.
--  Bản v2 làm mọi thứ file này làm + drop các policy cũ tạo tay qua Dashboard
--  ("Admin can view all orders" = using(true), nguyên nhân rò rỉ 14/07/2026) +
--  revoke quyền anon. Giữ file này chỉ để tham khảo lịch sử. Chạy v2 thay thế.
-- ============================================================
--  VÁ LỖ HỔNG BẢO MẬT NGHIÊM TRỌNG — bảng "orders" đang KHÔNG có
--  RLS chặn theo chủ đơn (hoặc RLS có nhưng chưa đúng/chưa bật).
-- ------------------------------------------------------------
--  ĐÃ KIỂM CHỨNG THẬT (2026-07-07): tạo 1 tài khoản test throwaway,
--  dùng token của tài khoản đó gọi thẳng REST API — và:
--    1) ĐỌC được TOÀN BỘ đơn hàng của MỌI khách khác (tên, SĐT, địa chỉ...)
--    2) SỬA được đơn hàng của người khác (đã test đổi field "note" của
--       1 đơn thật không phải của tài khoản test, thành công HTTP 200)
--  Nghĩa là hiện tại BẤT KỲ ai đăng nhập (kể cả tài khoản mới toanh,
--  chưa từng đặt đơn nào) đều có thể xem/sửa/hủy đơn của người khác
--  chỉ bằng cách gọi thẳng API — không cần công cụ hack đặc biệt.
--
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ bật RLS + thêm policy, không đụng dữ liệu.
--  Dùng lại hàm public.is_admin() đã có sẵn (định nghĩa trong
--  sql/schema-yenduyen.sql) để admin vẫn có toàn quyền như cũ.
-- ============================================================

alter table public.orders enable row level security;

-- Khách chỉ đọc được đơn của chính mình; admin đọc được tất cả
drop policy if exists orders_select_own on public.orders;
create policy orders_select_own on public.orders
  for select using (auth.uid() = user_id or public.is_admin());

-- Khách chỉ tạo được đơn đứng tên chính mình (checkout luôn bắt đăng nhập
-- nên user_id gửi lên luôn khớp auth.uid() ở luồng dùng bình thường)
drop policy if exists orders_insert_own on public.orders;
create policy orders_insert_own on public.orders
  for insert with check (auth.uid() = user_id);

-- Khách chỉ sửa được đơn của chính mình (vd. tự hủy đơn "Đợi xác nhận");
-- admin sửa được tất cả (đổi trạng thái, v.v.)
drop policy if exists orders_update_own on public.orders;
create policy orders_update_own on public.orders
  for update using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- Xoá đơn: chỉ admin (app hiện không có tính năng khách tự xoá đơn)
drop policy if exists orders_delete_admin on public.orders;
create policy orders_delete_admin on public.orders
  for delete using (public.is_admin());

grant select, insert, update on public.orders to authenticated;
