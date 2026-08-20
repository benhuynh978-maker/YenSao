-- ============================================================
--  VÁ LỖ HỔNG P0-1 — RÒ RỈ TOÀN BỘ BẢNG orders CHO NGƯỜI LẠ
-- ------------------------------------------------------------
--  ĐÃ KIỂM CHỨNG LIVE (14/07/2026): gọi REST API bằng anon key
--  (không đăng nhập) đọc được HẾT 16/16 đơn hàng — tên, SĐT,
--  địa chỉ, ghi chú, tổng tiền của mọi khách. Nghĩa là RLS trên
--  bảng orders CHƯA có hiệu lực (chưa bật, hoặc anon còn quyền đọc).
--  So sánh: profiles / addresses / contact_messages cùng lúc trả
--  về [] (RLS chặn đúng) — chỉ riêng orders bị hở.
--
--  File này THAY THẾ + mở rộng sql/fix-orders-rls.sql: ngoài việc
--  bật RLS + tạo policy, còn (a) DỌN sạch policy trùng từ
--  SETUP-DATABASE.sql, (b) THU HỒI quyền của anon.
--
--  CÁCH DÙNG: Supabase → SQL Editor → New query → dán TOÀN BỘ → Run.
--  AN TOÀN: chỉ bật RLS + policy + thu hồi quyền, KHÔNG đụng/không
--           xoá 1 dòng dữ liệu nào. Chạy lại nhiều lần vẫn an toàn.
--  Dùng lại hàm public.is_admin() có sẵn (SETUP-DATABASE.sql).
--  Xem CLAUDE.md mục "Kiến trúc bảo mật" (#4, #5) trước khi sửa.
-- ============================================================

-- 1) Bật Row Level Security cho orders
alter table public.orders enable row level security;

-- 2) Dọn sạch MỌI policy cũ trên orders — có tới 3 kiểu tên đã từng tạo:
--    (a) SETUP-DATABASE.sql: *_own_or_admin / *_self
--    (b) sql/fix-orders-rls.sql: *_own / *_admin
--    (c) POLICY CŨ TẠO TAY QUA DASHBOARD (tên có dấu cách) — trong đó
--        "Admin can view all orders" thực chất là FOR ALL USING(true) cho
--        public → CHO MỌI KHÁCH ĐĂNG NHẬP ĐỌC/SỬA/XOÁ MỌI ĐƠN. Đây chính
--        là policy khiến bản vá lần 1 chưa đóng được lỗ (kiểm chứng
--        14/07/2026: khách thường vẫn đọc 16/16 đơn). BẮT BUỘC drop.
drop policy if exists "orders_select_own_or_admin" on public.orders;
drop policy if exists "orders_insert_self"          on public.orders;
drop policy if exists "orders_update_own_or_admin"  on public.orders;
drop policy if exists orders_select_own   on public.orders;
drop policy if exists orders_insert_own   on public.orders;
drop policy if exists orders_update_own   on public.orders;
drop policy if exists orders_delete_admin on public.orders;
-- Policy cũ tạo tay qua Dashboard (BẮT BUỘC drop — nguyên nhân gốc còn sót):
drop policy if exists "Admin can view all orders" on public.orders;  -- 🎯 FOR ALL using(true) — mở toang
drop policy if exists "Users can insert orders"   on public.orders;  -- insert đứng tên user_id bất kỳ
drop policy if exists "Users can view own orders"  on public.orders;  -- trùng orders_select_own

-- 3) Tạo lại đúng 4 policy chuẩn theo chủ đơn (auth.uid) hoặc admin
-- Khách chỉ ĐỌC đơn của chính mình; admin đọc tất cả
create policy orders_select_own on public.orders
  for select using (auth.uid() = user_id or public.is_admin());

-- Khách chỉ TẠO đơn đứng tên chính mình (checkout luôn bắt đăng nhập)
create policy orders_insert_own on public.orders
  for insert with check (auth.uid() = user_id);

-- Khách chỉ SỬA đơn của mình (vd tự huỷ); admin sửa tất cả.
-- (Việc siết "chỉ được đổi cột/trạng thái nào" thuộc lỗ P2-3, làm ở bản vá sau.)
create policy orders_update_own on public.orders
  for update using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- XOÁ đơn: chỉ admin
create policy orders_delete_admin on public.orders
  for delete using (public.is_admin());

-- 4) Thu hồi mọi quyền cấp-bảng của anon: khách mua LUÔN phải đăng
--    nhập (dat-hang.html gọi requireAuth) nên anon không bao giờ cần
--    đụng tới orders. Đây là lớp chặn thứ 2 phòng khi RLS lỡ bị tắt.
revoke all on public.orders from anon;

-- 5) Bảo đảm authenticated vẫn đủ quyền cho luồng bình thường
grant select, insert, update on public.orders to authenticated;

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY (tuỳ chọn, chạy trong SQL Editor):
--    select relrowsecurity from pg_class where relname='orders';  -- phải = true
--    select policyname, cmd from pg_policies where tablename='orders'; -- đúng 4 dòng
--  Hoặc báo lại để kiểm chứng bằng REST anon key → phải trả về [].
-- ============================================================
