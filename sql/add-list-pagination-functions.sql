-- ============================================================
--  HÀM RPC PHỤC VỤ PHÂN TRANG PHÍA SERVER cho 2 trang admin có
--  dữ liệu KHÔNG PHẢI "1 bảng = 1 dòng" đơn giản:
--    - admin/khach-hang.html: danh sách hiện tại là dữ liệu TỔNG
--      HỢP (gộp orders theo SĐT, tính tier/doanh thu) — không thể
--      .range() thẳng trên bảng orders.
--    - admin/phan-hoi.html: danh sách hiện tại GHÉP 2 bảng khác
--      nhau (reviews + contact_messages) theo ngày — Supabase JS
--      không gộp 2 bảng trong 1 query được.
--
--  BẢO MẬT: cả 4 hàm đều SECURITY DEFINER (bypass RLS để đọc dữ
--  liệu tổng hợp/gộp bảng) NÊN BẮT BUỘC tự kiểm tra is_admin() ở
--  ngay đầu hàm — nếu không đây sẽ là lỗ hổng lộ toàn bộ tên/SĐT/
--  doanh thu khách hàng cho bất kỳ ai đã đăng nhập (không riêng gì
--  admin). Theo đúng CLAUDE.md: không tin gì ngoài xác thực lại
--  quyền admin tại chỗ, trong chính Postgres.
--
--  CÁCH DÙNG: dán TOÀN BỘ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm hàm (CREATE OR REPLACE), không đụng bảng/dữ
--  liệu cũ, chạy lại nhiều lần không lỗi.
-- ============================================================


-- ====================== 1) KHÁCH HÀNG — tổng hợp theo SĐT, phân trang ======================
-- Logic tier/doanh thu/tần suất MÔ PHỎNG ĐÚNG hàm buildCustomers() hiện có ở
-- admin/khach-hang.html (JS) — xem file đó nếu cần đối chiếu quy tắc gốc.
create or replace function public.list_customers_paginated(
  p_search text default null,
  p_tier   text default null,
  p_sort   text default 'recent',
  p_limit  int  default 20,
  p_offset int  default 0
)
returns table (
  phone_key        text,
  customer_name    text,
  customer_phone   text,
  province         text,
  total_orders     bigint,
  revenue          bigint,
  first_order_date timestamptz,
  last_order_date  timestamptz,
  tier             text,
  total_count      bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem danh sách khách hàng' using errcode = '42501';
  end if;

  return query
  with base as (
    select
      lower(regexp_replace(coalesce(o.customer_phone,''), '[^0-9]', '', 'g')) as phone_key,
      o.customer_name, o.customer_phone, o.customer_address, o.status, o.total_amount, o.created_at
    from public.orders o
    where o.customer_phone is not null and btrim(o.customer_phone) <> ''
  ),
  monthly_max as (
    select m.phone_key, max(m.cnt) as max_month_count
    from (
      select base.phone_key, date_trunc('month', base.created_at) as ym, count(*) as cnt
      from base where base.status <> 'cancelled'
      group by base.phone_key, date_trunc('month', base.created_at)
    ) m
    group by m.phone_key
  ),
  agg as (
    select
      b.phone_key,
      (array_agg(b.customer_name order by b.created_at desc))[1] as customer_name,
      (array_agg(b.customer_phone order by b.created_at desc))[1] as customer_phone,
      (array_agg(b.customer_address order by b.created_at desc))[1] as last_address,
      count(*) as total_orders,
      coalesce(sum(case when b.status <> 'cancelled' then b.total_amount else 0 end), 0)::bigint as revenue,
      max(b.created_at) as last_order_date,
      min(b.created_at) as first_order_date
    from base b
    group by b.phone_key
  ),
  final as (
    select
      a.phone_key, a.customer_name, a.customer_phone,
      nullif(trim(reverse(split_part(reverse(coalesce(a.last_address,'')), ',', 1))), '') as province,
      a.total_orders, a.revenue, a.first_order_date, a.last_order_date,
      -- Ưu tiên "có nguy cơ rời" (>30 ngày) trước, kể cả từng đạt VIP — khớp
      -- đúng thứ tự ưu tiên trong buildCustomers() ở JS.
      case
        when a.last_order_date < now() - interval '30 days' then 'churn'
        when coalesce(mm.max_month_count,0) >= 3 and a.revenue >= 10000000 then 'vip'
        when a.total_orders <= 2 then 'new'
        else 'regular'
      end as tier
    from agg a
    left join monthly_max mm on mm.phone_key = a.phone_key
  ),
  filtered as (
    select * from final f
    where (p_tier is null or p_tier = '' or f.tier = p_tier)
      and (
        p_search is null or btrim(p_search) = ''
        or f.customer_name ilike '%'||p_search||'%'
        or regexp_replace(coalesce(f.customer_phone,''), '[^0-9]', '', 'g') ilike '%'||regexp_replace(p_search,'[^0-9]','','g')||'%'
      )
  )
  select
    filtered.phone_key, filtered.customer_name, filtered.customer_phone, filtered.province,
    filtered.total_orders, filtered.revenue, filtered.first_order_date, filtered.last_order_date, filtered.tier,
    count(*) over() as total_count
  from filtered
  order by
    case p_sort
      when 'revenue' then filtered.revenue
      when 'orders'  then filtered.total_orders
      else extract(epoch from filtered.last_order_date)
    end desc,
    filtered.last_order_date desc
  limit greatest(p_limit, 0) offset greatest(p_offset, 0);
end;
$$;

revoke execute on function public.list_customers_paginated(text,text,text,int,int) from public;
revoke execute on function public.list_customers_paginated(text,text,text,int,int) from anon;
grant execute on function public.list_customers_paginated(text,text,text,int,int) to authenticated;


-- ── Lịch sử đơn của 1 khách (mở khi bấm SĐT/"Xem") — cùng cách chuẩn hoá SĐT ──
create or replace function public.list_orders_by_phone_key(p_phone_key text)
returns setof public.orders
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem lịch sử đơn hàng khách' using errcode = '42501';
  end if;

  return query
  select * from public.orders
  where lower(regexp_replace(coalesce(customer_phone,''), '[^0-9]', '', 'g')) = p_phone_key
  order by created_at desc;
end;
$$;

revoke execute on function public.list_orders_by_phone_key(text) from public;
revoke execute on function public.list_orders_by_phone_key(text) from anon;
grant execute on function public.list_orders_by_phone_key(text) to authenticated;


-- ====================== 2) PHẢN HỒI — gộp reviews + contact_messages, phân trang ======================
create or replace function public.list_feedback_paginated(
  p_type   text default null,  -- 'review' | 'contact' | null (tất cả)
  p_status text default null,  -- 'pending' | 'done' | null (tất cả)
  p_limit  int  default 20,
  p_offset int  default 0
)
returns table (
  item_type    text,
  id           uuid,
  name         text,
  created_at   timestamptz,
  rating       integer,
  content      text,
  product_name text,
  phone        text,
  done         boolean,
  total_count  bigint
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem phản hồi' using errcode = '42501';
  end if;

  return query
  with unioned as (
    select 'review'::text as item_type, r.id, r.customer_name as name, r.created_at,
           r.rating, r.content, p.name as product_name, null::text as phone,
           r.is_published as done
    from public.reviews r
    left join public.products p on p.id = r.product_id
    union all
    select 'contact'::text as item_type, c.id, c.name, c.created_at,
           null::integer as rating, c.message as content, null::text as product_name, c.phone,
           c.is_handled as done
    from public.contact_messages c
  ),
  filtered as (
    select * from unioned u
    where (p_type is null or p_type = '' or u.item_type = p_type)
      and (
        p_status is null or p_status = ''
        or (p_status = 'pending' and u.done = false)
        or (p_status = 'done' and u.done = true)
      )
  )
  select f.*, count(*) over() as total_count
  from filtered f
  order by f.created_at desc
  limit greatest(p_limit, 0) offset greatest(p_offset, 0);
end;
$$;

revoke execute on function public.list_feedback_paginated(text,text,int,int) from public;
revoke execute on function public.list_feedback_paginated(text,text,int,int) from anon;
grant execute on function public.list_feedback_paginated(text,text,int,int) to authenticated;


-- ── Thống kê tổng quan KHÔNG lọc/phân trang (thẻ số ở đầu trang Phản hồi) ──
create or replace function public.feedback_overview_stats()
returns table (total_count bigint, pending_count bigint, avg_rating numeric, satisfied_pct numeric)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem thống kê phản hồi' using errcode = '42501';
  end if;

  return query
  select
    (select count(*) from public.reviews) + (select count(*) from public.contact_messages) as total_count,
    (select count(*) from public.reviews where is_published = false) + (select count(*) from public.contact_messages where is_handled = false) as pending_count,
    (select round(avg(rating)::numeric, 1) from public.reviews where rating is not null) as avg_rating,
    (select case when count(*) filter (where rating is not null) > 0
       then round(100.0 * count(*) filter (where rating >= 4) / count(*) filter (where rating is not null))
       else null end
     from public.reviews) as satisfied_pct;
end;
$$;

revoke execute on function public.feedback_overview_stats() from public;
revoke execute on function public.feedback_overview_stats() from anon;
grant execute on function public.feedback_overview_stats() to authenticated;

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    - Gọi rpc('list_customers_paginated', {p_limit:20, p_offset:0}) bằng
--      tài khoản ADMIN → trả đúng danh sách + total_count.
--    - Gọi CÙNG hàm bằng tài khoản KHÁCH THƯỜNG (không phải admin) → PHẢI
--      bị từ chối (lỗi 42501), không trả bất kỳ dòng nào.
--    - Tương tự cho list_feedback_paginated/list_orders_by_phone_key/
--      feedback_overview_stats.
-- ============================================================
