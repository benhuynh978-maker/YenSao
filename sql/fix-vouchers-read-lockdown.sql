-- ============================================================
--  VÁ LỖ HỔNG P1-1 — LỘ TOÀN BỘ MÃ VOUCHER CHO NGƯỜI LẠ
--  GIAI ĐOẠN 3/3 (CUỐI): KHÓA BẢNG vouchers — chỉ admin đọc.
-- ------------------------------------------------------------
--  BỐI CẢNH: đã kiểm chứng LIVE (14/07/2026) anon gọi REST đọc được
--  TOÀN BỘ bảng vouchers (mọi mã + % giảm + giới hạn lượt) vì policy
--  cũ vouchers_read = using (is_active = true or is_admin()).
--
--  ĐIỀU KIỆN TIÊN QUYẾT (đã xong trước khi chạy file này):
--    - GĐ1: đã tạo hàm check_voucher (SECURITY DEFINER) + revoke anon.
--    - GĐ2: client (gio-hang/dat-hang) đã chuyển sang gọi rpc
--      check_voucher, KHÔNG còn from('vouchers') ở luồng khách.
--    - User đã TEST áp mã trên web thành công.
--
--  VÌ SAO KHÓA BẢNG KHÔNG GÃY TÍNH NĂNG:
--    - check_voucher chạy SECURITY DEFINER → bỏ qua RLS + grant, vẫn
--      đọc bảng để kiểm 1 mã. Khách áp mã đi qua RPC, không đụng bảng.
--    - Admin panel (admin/voucher.html, admin/dashboard.html) chạy dưới
--      phiên admin thật → is_admin()=true → vẫn qua policy vouchers_read.
--
--  BÀI HỌC P0-1 (orders): từng có policy ẩn tạo tay qua Dashboard làm
--  rò rỉ mà không nằm trong file SQL nào. Nên ở đây QUÉT SẠCH mọi policy
--  trên vouchers bằng DO-block động rồi tạo lại 2 policy chuẩn — không
--  tin vào danh sách tên policy.
--
--  CÁCH DÙNG: Supabase → SQL Editor → New query → dán TOÀN BỘ → Run.
--  Xem CLAUDE.md mục "Kiến trúc bảo mật".
-- ============================================================

-- 1) Đảm bảo RLS bật (phòng khi bị tắt tay).
alter table public.vouchers enable row level security;

-- 2) Quét SẠCH mọi policy đang có trên public.vouchers (kể cả policy ẩn
--    tạo tay qua Dashboard) rồi tạo lại 2 policy chuẩn ở bước 3.
do $$
declare pol record;
begin
  for pol in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'vouchers'
  loop
    execute format('drop policy if exists %I on public.vouchers;', pol.policyname);
  end loop;
end $$;

-- 3) Hai policy chuẩn: CHỈ admin đọc; admin toàn quyền CRUD.
create policy vouchers_read on public.vouchers
  for select using (public.is_admin());

create policy vouchers_admin on public.vouchers
  for all using (public.is_admin()) with check (public.is_admin());

-- 4) Chặn ở tầng grant: anon không còn quyền đọc bảng (đã hết cả RLS lẫn
--    grant → REST trả 401). authenticated vẫn giữ grant nhưng RLS lọc để
--    chỉ admin thấy hàng; insert/update/delete vẫn chỉ authenticated (admin).
revoke select on public.vouchers from anon;

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    (a) ANON gọi REST đọc bảng → 401 (permission denied):
--        curl 'https://<proj>.supabase.co/rest/v1/vouchers?select=*' \
--             -H 'apikey: <anon key>'
--    (b) KHÁCH đăng nhập thường select vouchers → [] (RLS lọc hết).
--    (c) ADMIN đăng nhập → select vouchers → thấy đủ mã.
--    (d) Web: khách áp mã trong giỏ/đặt hàng → VẪN chạy (qua rpc check_voucher).
--    (e) Admin panel voucher: liệt kê / thêm / sửa / xóa → VẪN chạy.
--  Nếu (d) hoặc (e) gãy → báo ngay, có thể tạm mở lại policy cũ bằng:
--    create policy vouchers_read on public.vouchers
--      for select using (is_active = true or public.is_admin());
--    grant select on public.vouchers to anon;
-- ============================================================
