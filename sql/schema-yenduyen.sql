-- ============================================================
--  CƠ SỞ DỮ LIỆU — Yến Sào Yến Duyên (BẢN GỌN)
-- ------------------------------------------------------------
--  CÁCH DÙNG (không cần biết SQL):
--    1. Mở Supabase → vào dự án của bạn.
--    2. Bấm menu trái: "SQL Editor" → "New query".
--    3. Dán TOÀN BỘ file này vào → bấm nút "Run".
--    4. Xong: 5 bảng mới được tạo, kèm bảo mật.
--
--  AN TOÀN: chạy lại nhiều lần cũng không lỗi
--           (dùng IF NOT EXISTS / DROP POLICY IF EXISTS).
--
--  GỒM 5 KHO DỮ LIỆU:
--    products          — Sản phẩm
--    vouchers          — Mã giảm giá
--    blog_posts        — Bài viết
--    reviews           — Đánh giá
--    contact_messages  — Tin nhắn liên hệ
--
--  BẢO MẬT (RLS):
--    - Khách (chưa đăng nhập): chỉ ĐỌC sản phẩm/bài viết/voucher
--      đang bật; được GỬI đánh giá & liên hệ.
--    - Admin (profiles.role = 'admin'): TOÀN QUYỀN.
-- ============================================================


-- ── Hàm kiểm tra "có phải admin không" ──────────────────────
-- Dựa trên bảng profiles đã có sẵn (cột role = 'admin').
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;


-- ====================== 1) PRODUCTS — Sản phẩm ======================
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text   not null,
  price       bigint not null default 0,   -- giá bán (VNĐ)
  old_price   bigint,                       -- giá gạch ngang (để trống nếu không giảm)
  image_url   text,                         -- ảnh sản phẩm
  category    text,                         -- danh mục (để lọc)
  badge       text,                         -- nhãn: hot/new/gift/sale (để trống nếu không có)
  description text,                         -- mô tả
  stock       integer not null default 0,   -- tồn kho
  is_active   boolean not null default true,-- hiện/ẩn (thay vì xoá)
  created_at  timestamptz not null default now()
);
-- Nếu bảng products đã tạo trước đó mà chưa có cột badge thì thêm vào (an toàn chạy lại):
alter table public.products add column if not exists badge text;

alter table public.products enable row level security;

-- Khách đọc được SP đang bật; admin đọc tất cả
drop policy if exists products_read on public.products;
create policy products_read on public.products
  for select using (is_active = true or public.is_admin());

-- Chỉ admin được thêm/sửa/xoá
drop policy if exists products_admin on public.products;
create policy products_admin on public.products
  for all using (public.is_admin()) with check (public.is_admin());

grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;


-- ====================== 2) VOUCHERS — Mã giảm giá ======================
create table if not exists public.vouchers (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,        -- mã (VD: YENDUYEN10)
  discount_type  text not null default 'percent', -- 'percent' (%) hoặc 'amount' (đ)
  discount_value bigint not null default 0,   -- giá trị giảm
  min_order      bigint not null default 0,   -- đơn tối thiểu
  end_date       timestamptz,                 -- ngày hết hạn (để trống = không hết hạn)
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);
alter table public.vouchers enable row level security;

-- CHỈ admin đọc bảng (chống lộ toàn bộ mã cho người lạ — P1-1). Khách áp mã
-- KHÔNG đọc bảng nữa mà gọi rpc check_voucher (SECURITY DEFINER, bỏ qua RLS).
-- Xem sql/fix-vouchers-read-lockdown.sql + sql/add-voucher-check-function.sql.
drop policy if exists vouchers_read on public.vouchers;
create policy vouchers_read on public.vouchers
  for select using (public.is_admin());

drop policy if exists vouchers_admin on public.vouchers;
create policy vouchers_admin on public.vouchers
  for all using (public.is_admin()) with check (public.is_admin());

-- anon KHÔNG có quyền đọc bảng (chỉ dùng mã qua rpc check_voucher).
grant select on public.vouchers to authenticated;
grant insert, update, delete on public.vouchers to authenticated;


-- ====================== 3) BLOG_POSTS — Bài viết ======================
create table if not exists public.blog_posts (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  content      text,                          -- nội dung bài viết
  cover_image  text,                          -- ảnh bìa
  topic        text,                          -- chủ đề (để lọc)
  is_published boolean not null default false,-- đã xuất bản hay nháp
  created_at   timestamptz not null default now()
);
alter table public.blog_posts enable row level security;

-- Khách đọc bài đã xuất bản; admin đọc tất cả (kể cả nháp)
drop policy if exists blog_read on public.blog_posts;
create policy blog_read on public.blog_posts
  for select using (is_published = true or public.is_admin());

drop policy if exists blog_admin on public.blog_posts;
create policy blog_admin on public.blog_posts
  for all using (public.is_admin()) with check (public.is_admin());

grant select on public.blog_posts to anon, authenticated;
grant insert, update, delete on public.blog_posts to authenticated;


-- ====================== 4) REVIEWS — Đánh giá ======================
create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid references public.products(id) on delete set null, -- SP được đánh giá (có thể trống)
  customer_name text not null,
  rating        integer check (rating between 1 and 5),  -- số sao 1–5
  content       text,
  is_published  boolean not null default false,          -- admin duyệt mới hiện lên web
  created_at    timestamptz not null default now()
);
alter table public.reviews enable row level security;

-- Khách đọc đánh giá đã duyệt; admin đọc tất cả
drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews
  for select using (is_published = true or public.is_admin());

-- Ai cũng được GỬI đánh giá NHƯNG người thường buộc is_published=false
-- (chờ admin duyệt) — chống tự-publish (lỗ P1-2). Bản này KHÔNG tham chiếu
-- cột order_id để chạy được cả khi chưa chạy sql/add-review-order-link.sql.
-- Bản ĐẦY ĐỦ (kèm logic gắn đơn hàng) nằm ở sql/add-review-order-link.sql —
-- chạy file đó SAU file này sẽ nâng cấp policy lên bản đầy đủ. Không tạo thêm
-- file nào khác định nghĩa lại reviews_insert (tránh "đá nhau").
drop policy if exists reviews_insert on public.reviews;
create policy reviews_insert on public.reviews
  for insert with check (public.is_admin() or is_published = false);

-- Admin sửa/xoá/duyệt
drop policy if exists reviews_admin on public.reviews;
create policy reviews_admin on public.reviews
  for all using (public.is_admin()) with check (public.is_admin());

grant select, insert on public.reviews to anon, authenticated;
grant update, delete on public.reviews to authenticated;


-- ============== 5) CONTACT_MESSAGES — Tin nhắn liên hệ ==============
create table if not exists public.contact_messages (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  phone       text,
  message     text,
  is_handled  boolean not null default false,  -- đã xử lý chưa
  created_at  timestamptz not null default now()
);
alter table public.contact_messages enable row level security;

-- Ai cũng GỬI được liên hệ
drop policy if exists contact_insert on public.contact_messages;
create policy contact_insert on public.contact_messages
  for insert with check (true);

-- CHỈ admin được đọc/sửa/xoá (khách không xem được tin của người khác)
drop policy if exists contact_admin on public.contact_messages;
create policy contact_admin on public.contact_messages
  for all using (public.is_admin()) with check (public.is_admin());

grant insert on public.contact_messages to anon, authenticated;
grant select, update, delete on public.contact_messages to authenticated;


-- ============================================================
--  XONG. Sau khi chạy, vào Supabase → Table Editor để thấy
--  5 bảng mới. Lúc này chúng còn TRỐNG (chưa có dữ liệu) —
--  bạn sẽ thêm dữ liệu qua trang admin ở các bước sau.
-- ============================================================
