-- ============================================================
--  HỆ THỐNG THÔNG BÁO ADMIN (mới, TÁCH BIỆT hoàn toàn với toast
--  lỗi/lưu ý thông thường) — gộp tin từ 6 hệ thống: đơn hàng,
--  khách hàng, phản hồi, voucher, flash sale, sản phẩm.
-- ------------------------------------------------------------
--  GỒM:
--    admin_notifications         — 1 bảng chung, cột chia theo hệ
--                                   thống (đơn hàng→khách hàng→
--                                   phản hồi→voucher→flashsale→sản phẩm)
--    trg_notify_orders            — đơn mới / khách hủy / khách mới /
--                                    voucher dùng hết (theo sự kiện)
--    trg_notify_reviews           — review mới (theo sự kiện)
--    trg_notify_contact           — liên hệ mới (theo sự kiện)
--    trg_notify_flash_sale_items  — hết suất 1 SP / hết suất cả đợt
--    trg_notify_products          — hết hàng / sắp hết hàng (<5)
--    scan_time_based_admin_notifications — quét mỗi ngày (pg_cron):
--                                    voucher hết hạn, flash sale kết
--                                    thúc, khách sắp rời tier (báo
--                                    trước 3 ngày so với mốc 30 ngày
--                                    tự chuyển 'churn')
--
--  BẢO MẬT (đúng CLAUDE.md):
--    - RLS bật, CHỈ is_admin() được đọc/tick đã đọc — không có policy
--      insert/delete cho bất kỳ vai trò nào (giống flash_sale_purchases):
--      chỉ hàm SECURITY DEFINER (chủ bảng) mới ghi được, xuyên qua RLS.
--    - Bật Realtime cho bảng để đẩy thông báo tức thời tới mọi tab admin
--      đang mở, không cần bật tay trong Dashboard.
--    - orders.id là BIGINT (đã xác nhận ở sql/add-review-order-link.sql,
--      KHÔNG phải uuid như SETUP-DATABASE.sql ghi) — dùng đúng kiểu này.
--
--  CÁCH DÙNG: dán TOÀN BỘ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chạy lại nhiều lần không lỗi (IF NOT EXISTS / DROP TRIGGER
--  IF EXISTS / CREATE OR REPLACE). Cần đã chạy sql/schema-yenduyen.sql,
--  sql/add-customer-tier.sql, sql/add-voucher-limits.sql,
--  sql/add-flash-sale.sql, sql/add-review-order-link.sql trước đó.
-- ============================================================


-- ====================== 1) BẢNG admin_notifications ======================
create table if not exists public.admin_notifications (
  id           uuid primary key default gen_random_uuid(),
  system       text not null check (system in ('order','customer','feedback','voucher','flashsale','product')),
  event_type   text not null,
  title        text not null,
  content      text not null,

  -- ── Đơn hàng ──
  order_id     bigint references public.orders(id) on delete set null,
  order_code   text,

  -- ── Khách hàng ──
  customer_user_id uuid references auth.users(id) on delete set null,
  customer_name    text,
  customer_phone   text,
  customer_tier    text,

  -- ── Phản hồi (review hoặc liên hệ) ──
  feedback_rating         integer,
  feedback_product_name   text,
  feedback_customer_name  text,
  feedback_customer_phone text,

  -- ── Voucher ──
  voucher_code text,

  -- ── Flash sale ──
  flash_sale_id           uuid references public.flash_sales(id) on delete set null,
  flash_sale_name         text,
  flash_sale_product_name text,

  -- ── Sản phẩm ──
  product_id    uuid references public.products(id) on delete set null,
  product_name  text,
  product_stock integer,

  is_read     boolean not null default false,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists idx_admin_notif_created on public.admin_notifications (created_at desc);
create index if not exists idx_admin_notif_unread on public.admin_notifications (created_at desc) where is_read = false;
create index if not exists idx_admin_notif_system on public.admin_notifications (system);

alter table public.admin_notifications enable row level security;

-- Chỉ admin đọc + tick đã đọc. KHÔNG có policy insert/delete cho bất kỳ
-- vai trò nào — chỉ các hàm SECURITY DEFINER bên dưới (chủ bảng) ghi được.
drop policy if exists admin_notifications_select on public.admin_notifications;
create policy admin_notifications_select on public.admin_notifications
  for select using (public.is_admin());

drop policy if exists admin_notifications_update on public.admin_notifications;
create policy admin_notifications_update on public.admin_notifications
  for update using (public.is_admin()) with check (public.is_admin());

grant select, update on public.admin_notifications to authenticated;

-- Bật Realtime để đẩy thông báo tức thời tới mọi tab admin đang mở.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'admin_notifications'
  ) then
    alter publication supabase_realtime add table public.admin_notifications;
  end if;
end $$;


-- ====================== 2) ĐƠN HÀNG — đơn mới / khách hủy / khách mới / voucher dùng hết ======================
create or replace function public.trg_notify_orders()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prior_orders int;
  v_voucher      public.vouchers;
  v_total_used   int;
begin
  if TG_OP = 'INSERT' then
    insert into public.admin_notifications(system, event_type, title, content, order_id, order_code)
    values ('order', 'new_order', 'Đơn hàng mới',
      '1 đơn hàng mới ' || coalesce(new.order_code, new.id::text),
      new.id, new.order_code);

    if new.user_id is not null then
      select count(*) into v_prior_orders from public.orders
        where user_id = new.user_id and id <> new.id;
      if v_prior_orders = 0 then
        insert into public.admin_notifications(
          system, event_type, title, content,
          customer_user_id, customer_name, customer_phone, customer_tier
        ) values (
          'customer', 'new_customer', 'Khách hàng mới',
          'Chúng ta có khách hàng mới ' || coalesce(new.customer_name, '') || ' ' ||
            coalesce(new.customer_phone, '') || ' đầu tiên đặt hàng',
          new.user_id, new.customer_name, new.customer_phone,
          (select customer_tier from public.profiles where id = new.user_id)
        );
      end if;
    end if;

    if new.voucher_code is not null and new.status <> 'cancelled' then
      select * into v_voucher from public.vouchers where code = new.voucher_code;
      if v_voucher.id is not null then
        select count(*) into v_total_used from public.orders
          where voucher_code = v_voucher.code and status <> 'cancelled';
        if v_total_used >= coalesce(v_voucher.total_quantity, 1) then
          insert into public.admin_notifications(system, event_type, title, content, voucher_code)
          values ('voucher', 'voucher_used_up', 'Voucher đã dùng hết',
            'Voucher mã ' || v_voucher.code || ' đã dùng hết', v_voucher.code);
        end if;
      end if;
    end if;

  elsif TG_OP = 'UPDATE' then
    if new.status = 'cancelled' and old.status <> 'cancelled' and new.cancelled_by = 'customer' then
      insert into public.admin_notifications(system, event_type, title, content, order_id, order_code)
      values ('order', 'order_cancelled', 'Đơn hàng bị hủy',
        'Đơn hàng ' || coalesce(new.order_code, new.id::text) || ' đã bị hủy bởi khách hàng',
        new.id, new.order_code);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_orders_notify on public.orders;
create trigger trg_orders_notify
  after insert or update on public.orders
  for each row execute function public.trg_notify_orders();


-- ====================== 3) PHẢN HỒI — review mới / liên hệ mới ======================
create or replace function public.trg_notify_reviews()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product_name text;
  v_phone        text;
begin
  select name into v_product_name from public.products where id = new.product_id;
  if new.order_id is not null then
    select customer_phone into v_phone from public.orders where id = new.order_id;
  end if;

  insert into public.admin_notifications(
    system, event_type, title, content,
    feedback_rating, feedback_product_name, feedback_customer_name, feedback_customer_phone
  ) values (
    'feedback', 'new_review', 'Đánh giá mới',
    'Có một đánh giá mới ' || coalesce(new.rating::text, '?') || ' sao về ' ||
      coalesce(v_product_name, 'sản phẩm') || ' từ ' || new.customer_name ||
      case when v_phone is not null then ' ' || v_phone else '' end,
    new.rating, v_product_name, new.customer_name, v_phone
  );
  return new;
end;
$$;

drop trigger if exists trg_reviews_notify on public.reviews;
create trigger trg_reviews_notify
  after insert on public.reviews
  for each row execute function public.trg_notify_reviews();


create or replace function public.trg_notify_contact()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_notifications(
    system, event_type, title, content,
    feedback_customer_name, feedback_customer_phone
  ) values (
    'feedback', 'new_contact', 'Liên hệ mới',
    'Khách ' || new.name || ' có số ' || coalesce(new.phone, '(không để lại)') || ' muốn liên hệ với bạn',
    new.name, new.phone
  );
  return new;
end;
$$;

drop trigger if exists trg_contact_notify on public.contact_messages;
create trigger trg_contact_notify
  after insert on public.contact_messages
  for each row execute function public.trg_notify_contact();


-- ====================== 4) FLASH SALE — hết suất 1 SP / hết suất cả đợt ======================
create or replace function public.trg_notify_flash_sale_items()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product_name text;
  v_fs_name      text;
  v_remaining    int;
begin
  if new.sold_count >= new.stock_limit and old.sold_count < old.stock_limit then
    select name into v_product_name from public.products where id = new.product_id;
    select name into v_fs_name from public.flash_sales where id = new.flash_sale_id;

    insert into public.admin_notifications(
      system, event_type, title, content,
      flash_sale_id, flash_sale_name, flash_sale_product_name, product_id, product_name
    ) values (
      'flashsale', 'item_soldout', 'Flash Sale hết suất',
      coalesce(v_product_name, 'Sản phẩm') || ' đã hết suất trong chương trình ' || coalesce(v_fs_name, 'Flash Sale'),
      new.flash_sale_id, v_fs_name, v_product_name, new.product_id, v_product_name
    );

    select count(*) into v_remaining from public.flash_sale_items
      where flash_sale_id = new.flash_sale_id and sold_count < stock_limit;

    if v_remaining = 0 and not exists (
      select 1 from public.admin_notifications
      where event_type = 'flashsale_all_soldout' and flash_sale_id = new.flash_sale_id
    ) then
      insert into public.admin_notifications(system, event_type, title, content, flash_sale_id, flash_sale_name)
      values ('flashsale', 'flashsale_all_soldout', 'Flash Sale hết suất toàn bộ',
        'Toàn bộ sản phẩm trong chương trình ' || coalesce(v_fs_name, 'Flash Sale') || ' đã hết suất',
        new.flash_sale_id, v_fs_name);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_flash_sale_items_notify on public.flash_sale_items;
create trigger trg_flash_sale_items_notify
  after update on public.flash_sale_items
  for each row execute function public.trg_notify_flash_sale_items();


-- ====================== 5) SẢN PHẨM — hết hàng / sắp hết hàng (<5) ======================
create or replace function public.trg_notify_products()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.stock <= 0 and old.stock > 0 then
    insert into public.admin_notifications(system, event_type, title, content, product_id, product_name, product_stock)
    values ('product', 'out_of_stock', 'Sản phẩm hết hàng',
      'Sản phẩm ' || new.name || ' đã hết hàng', new.id, new.name, new.stock);
  elsif new.stock < 5 and new.stock > 0 and old.stock >= 5 then
    insert into public.admin_notifications(system, event_type, title, content, product_id, product_name, product_stock)
    values ('product', 'low_stock', 'Sản phẩm sắp hết hàng',
      'Sản phẩm ' || new.name || ' chỉ còn ' || new.stock || ' sản phẩm cuối', new.id, new.name, new.stock);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_products_notify on public.products;
create trigger trg_products_notify
  after update of stock on public.products
  for each row execute function public.trg_notify_products();


-- ====================== 6) QUÉT ĐỊNH KỲ — voucher hết hạn / flash sale kết thúc / khách sắp rời tier ======================
-- 3 loại này đổi theo THỜI GIAN TRÔI QUA (không phải sự kiện ghi dữ liệu),
-- nên không thể bắt bằng trigger — cần quét mỗi ngày bằng pg_cron, giống
-- lý do recompute_customer_tier() ở sql/add-customer-tier.sql đã cần cron.
-- Mỗi mục CHỈ báo 1 LẦN DUY NHẤT (dedupe bằng "not exists" trên chính bảng
-- admin_notifications) — không lặp lại thông báo giống hệt mỗi ngày.
create or replace function public.scan_time_based_admin_notifications()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  -- Voucher hết hạn
  for r in
    select v.* from public.vouchers v
    where v.end_date is not null and v.end_date < now()
      and not exists (
        select 1 from public.admin_notifications n
        where n.event_type = 'voucher_expired' and n.voucher_code = v.code
      )
  loop
    insert into public.admin_notifications(system, event_type, title, content, voucher_code)
    values ('voucher', 'voucher_expired', 'Voucher hết hạn',
      'Voucher mã ' || r.code || ' đã hết hạn', r.code);
  end loop;

  -- Flash sale kết thúc
  for r in
    select fs.* from public.flash_sales fs
    where fs.end_at < now()
      and not exists (
        select 1 from public.admin_notifications n
        where n.event_type = 'flashsale_ended' and n.flash_sale_id = fs.id
      )
  loop
    insert into public.admin_notifications(system, event_type, title, content, flash_sale_id, flash_sale_name)
    values ('flashsale', 'flashsale_ended', 'Flash Sale kết thúc',
      'Flash sale ' || coalesce(r.name, '') || ' đã kết thúc', r.id, r.name);
  end loop;

  -- Khách sắp rơi vào nhóm "có nguy cơ rời" — báo trước 3 ngày so với mốc 30
  -- ngày mà recompute_customer_tier() tự chuyển sang 'churn' (add-customer-tier.sql).
  for r in
    select p.id as user_id, p.customer_tier, o.last_order, o.customer_name, o.customer_phone
    from public.profiles p
    join lateral (
      select max(created_at) as last_order,
        (array_agg(customer_name order by created_at desc))[1] as customer_name,
        (array_agg(customer_phone order by created_at desc))[1] as customer_phone
      from public.orders where user_id = p.id
    ) o on true
    where o.last_order is not null
      and o.last_order between now() - interval '30 days' and now() - interval '27 days'
      and not exists (
        select 1 from public.admin_notifications n
        where n.event_type = 'tier_at_risk' and n.customer_user_id = p.id and n.created_at > o.last_order
      )
  loop
    insert into public.admin_notifications(
      system, event_type, title, content, customer_user_id, customer_name, customer_phone, customer_tier
    ) values (
      'customer', 'tier_at_risk', 'Khách sắp rời nhóm',
      trim(coalesce(r.customer_name, '') || ' ' || coalesce(r.customer_phone, '') || ' ' ||
        coalesce(r.customer_tier, '')) || ' đã lâu rồi chưa đặt hàng',
      r.user_id, r.customer_name, r.customer_phone, r.customer_tier
    );
  end loop;
end;
$$;

create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'admin-notifications-daily-scan') then
    perform cron.unschedule('admin-notifications-daily-scan');
  end if;
end $$;

-- 19:05 UTC = 02:05 sáng giờ VN, chạy sau job tính tier (19:00 UTC) 5 phút.
select cron.schedule(
  'admin-notifications-daily-scan',
  '5 19 * * *',
  $$ select public.scan_time_based_admin_notifications(); $$
);

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    - Đặt 1 đơn hàng thật → admin_notifications có dòng 'new_order'.
--    - Khách tự hủy đơn (don-hang-cua-toi.html) → có dòng 'order_cancelled'.
--    - Tài khoản mới đặt đơn đầu tiên → có thêm dòng 'new_customer'.
--    - Review/liên hệ mới → có dòng 'new_review'/'new_contact'.
--    - Bán hết suất Flash Sale 1 sản phẩm → dòng 'item_soldout'; bán hết
--      NỐT sản phẩm cuối cùng của cả đợt → thêm dòng 'flashsale_all_soldout'.
--    - Sửa tồn kho sản phẩm về 0 hoặc dưới 5 (từ ≥5) → dòng tương ứng.
--    - Chạy tay: select public.scan_time_based_admin_notifications();
--      → tạo dòng cho voucher/flash sale/khách đã tới mốc thời gian.
--    - Gọi lại hàm quét lần 2 ngay sau đó → KHÔNG tạo thêm dòng trùng.
-- ============================================================
