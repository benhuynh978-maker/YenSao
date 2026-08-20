-- ============================================================
--  THÔNG TIN CỬA HÀNG (site_settings) — Hotline / Zalo / Facebook /
--  Tên cửa hàng / Email / Địa chỉ
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ tạo bảng/policy/cột, chạy lại nhiều lần không lỗi.
--
--  Bảng chỉ có ĐÚNG 1 dòng (id = 1) — nơi duy nhất lưu thông tin
--  cửa hàng thật. admin/cai-dat.html đọc/ghi dòng này.
--  js/site-contact.js chạy trên mọi trang khách hàng để thay
--  Hotline/Zalo/Facebook/Email/Địa chỉ viết cứng trong HTML bằng
--  giá trị thật (nếu tải dữ liệu lỗi thì giữ nguyên viết cứng có
--  sẵn — không làm hỏng trang). Riêng "Tên cửa hàng" hiện CHỈ lưu
--  vào Supabase, CHƯA hiển thị ra trang khách hàng (sẽ dùng ở chỗ
--  khác sau, theo yêu cầu 13/07).
-- ============================================================

create table if not exists public.site_settings (
  id           integer primary key default 1,
  phone        text,
  zalo_phone   text,
  facebook_url text,
  shop_name    text,
  email        text,
  address      text,
  updated_at   timestamptz default now(),
  constraint site_settings_singleton check (id = 1)
);

-- Chạy lại file cũ (đã tạo bảng thiếu 3 cột này) vẫn an toàn — lệnh dưới tự
-- thêm cột còn thiếu, không đụng dữ liệu đã lưu.
alter table public.site_settings add column if not exists shop_name text;
alter table public.site_settings add column if not exists email text;
alter table public.site_settings add column if not exists address text;

insert into public.site_settings (id) values (1) on conflict (id) do nothing;

alter table public.site_settings enable row level security;

-- Ai cũng đọc được (trang khách hàng cần đọc để hiện số/link đúng)
drop policy if exists site_settings_select_all on public.site_settings;
create policy site_settings_select_all on public.site_settings
  for select using (true);

-- Chỉ admin thật (profiles.role = 'admin') mới được sửa
drop policy if exists site_settings_update_admin on public.site_settings;
create policy site_settings_update_admin on public.site_settings
  for update using (public.is_admin());

-- Cấp quyền cấp BẢNG (bắt buộc — thiếu bước này thì RLS phía trên vô nghĩa,
-- anon/authenticated sẽ bị chặn truy cập trước khi RLS kịp xét tới)
grant select on public.site_settings to anon, authenticated;
grant update on public.site_settings to authenticated;
