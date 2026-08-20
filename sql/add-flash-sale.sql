-- ============================================================
--  FLASH SALE — bảng dữ liệu + tích hợp vào luồng đặt hàng thật.
-- ------------------------------------------------------------
--  GỒM:
--    flash_sales          — từng đợt/khung giờ sale (tên, giờ bắt đầu/kết thúc)
--    flash_sale_items      — sản phẩm nào tham gia đợt nào (giá sale, số suất,
--                            đã bán, giới hạn mua/khách)
--    flash_sale_purchases  — nhật ký ai đã mua bao nhiêu suất (chỉ để tính
--                            giới hạn mua/khách, KHÔNG public, chỉ trigger
--                            SECURITY DEFINER bên dưới được đọc/ghi)
--
--  BẢO MẬT (đúng nguyên tắc CLAUDE.md — không tin số liệu client gửi):
--    - Giá sale/số suất còn lại/giới hạn mua đều được XÁC THỰC LẠI ở đây,
--      trong CHÍNH trigger validate_order_price() đã có (sql/add-order-
--      price-validation.sql) — không thêm luồng insert đơn hàng mới nào,
--      không đổi kiến trúc trang dat-hang.html/gio-hang.html.
--    - Chống bán vượt suất bằng UPDATE nguyên tử có điều kiện + khoá dòng
--      "for update" (giống kỹ thuật đã dùng cho tồn kho sản phẩm thật).
--    - Khách gửi kèm "flashSaleItemId" trong từng item giỏ hàng — nếu sai/
--      giả mạo (khác sản phẩm, hết suất, hết giờ, vượt giới hạn mua) thì
--      CHẶN CẢ ĐƠN bằng lỗi mã FS01 (giống STK01 đã có), không âm thầm
--      đổi giá — khách phải quay lại giỏ hàng.
--    - flash_sales/flash_sale_items: ai cũng ĐỌC được (dữ liệu marketing,
--      không nhạy cảm), CHỈ ADMIN được ghi (dùng lại hàm is_admin() có sẵn).
--
--  CÁCH DÙNG: dán TOÀN BỘ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chạy lại nhiều lần không lỗi (IF NOT EXISTS / DROP POLICY IF EXISTS
--  / CREATE OR REPLACE). Cần đã chạy sql/schema-yenduyen.sql (hàm is_admin())
--  và sql/add-order-price-validation.sql trước đó.
-- ============================================================


-- ====================== 1) FLASH_SALES — Đợt/khung giờ sale ======================
create table if not exists public.flash_sales (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  start_at   timestamptz not null,
  end_at     timestamptz not null,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.flash_sales enable row level security;

drop policy if exists flash_sales_read on public.flash_sales;
create policy flash_sales_read on public.flash_sales
  for select using (is_active = true or public.is_admin());

drop policy if exists flash_sales_admin on public.flash_sales;
create policy flash_sales_admin on public.flash_sales
  for all using (public.is_admin()) with check (public.is_admin());

grant select on public.flash_sales to anon, authenticated;
grant insert, update, delete on public.flash_sales to authenticated;


-- ====================== 2) FLASH_SALE_ITEMS — Sản phẩm trong đợt ======================
create table if not exists public.flash_sale_items (
  id                 uuid primary key default gen_random_uuid(),
  flash_sale_id      uuid not null references public.flash_sales(id) on delete cascade,
  product_id         uuid not null references public.products(id) on delete cascade,
  sale_price         bigint not null,               -- giá bán trong đợt sale
  stock_limit        integer not null,               -- số suất giới hạn riêng cho đợt (KHÁC tồn kho thật)
  sold_count         integer not null default 0,     -- đã bán bao nhiêu suất (chỉ trigger bên dưới được cộng)
  per_customer_limit integer,                        -- để trống = không giới hạn mua/khách
  created_at         timestamptz not null default now(),
  unique (flash_sale_id, product_id)
);

alter table public.flash_sale_items enable row level security;

drop policy if exists flash_sale_items_read on public.flash_sale_items;
create policy flash_sale_items_read on public.flash_sale_items
  for select using (true);

drop policy if exists flash_sale_items_admin on public.flash_sale_items;
create policy flash_sale_items_admin on public.flash_sale_items
  for all using (public.is_admin()) with check (public.is_admin());

grant select on public.flash_sale_items to anon, authenticated;
grant insert, update, delete on public.flash_sale_items to authenticated;


-- ====================== 3) FLASH_SALE_PURCHASES — Nhật ký mua (nội bộ) ======================
-- KHÔNG cấp quyền cho anon/authenticated — chỉ hàm SECURITY DEFINER (chạy với
-- quyền chủ hàm) mới đọc/ghi được, giống cách schema `security` bị khoá hẳn.
create table if not exists public.flash_sale_purchases (
  id                 bigint generated always as identity primary key,
  flash_sale_item_id uuid not null references public.flash_sale_items(id) on delete cascade,
  customer_key       text not null,  -- user_id (dạng text) nếu đăng nhập, hoặc SĐT nếu khách vãng lai
  qty                integer not null,
  created_at         timestamptz not null default now()
);

create index if not exists idx_fs_purchases_lookup
  on public.flash_sale_purchases (flash_sale_item_id, customer_key);

alter table public.flash_sale_purchases enable row level security;
-- Cố tình KHÔNG tạo policy nào — RLS bật + không policy = mọi vai trò thường
-- (anon/authenticated) bị chặn hoàn toàn, chỉ SECURITY DEFINER mới xuyên qua được.


-- ====================== 4) MỞ RỘNG validate_order_price() — áp giá Flash Sale ======================
-- Đây là bản THAY THẾ HOÀN TOÀN cho hàm trong sql/add-order-price-validation.sql —
-- giữ nguyên 100% logic cũ (giá thật/tồn kho/voucher/phí ship), CHỈ thêm bước
-- kiểm tra + áp giá Flash Sale ngay sau khi đã xác định unit_price thật từ
-- products. Dán đè lên bản cũ (CREATE OR REPLACE), không cần chạy lại file cũ.
create or replace function public.validate_order_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  item          jsonb;
  clean_id      text;
  qty           integer;
  unit_price    bigint;
  live_stock    integer;
  new_items     jsonb := '[]'::jsonb;
  subtotal      bigint := 0;
  item_count    integer := 0;
  v             record;
  eligible      bigint;
  discount      bigint := 0;
  voucher_ok    boolean := false;
  ship_fee      bigint := 0;
  free_ship_at  constant bigint := 500000;  -- khớp FREE_SHIP_THRESHOLD ở dat-hang.html
  flat_ship_fee constant bigint := 35000;   -- khớp FLAT_SHIPPING_FEE ở dat-hang.html
  prior_orders  integer;
  total_used    integer;
  my_used       integer;
  -- ── Flash Sale ──
  fs_item_id    text;
  fs_row        record;
  fs_used       integer;
  fs_applied    boolean;
  v_customer_key text;
begin
  -- Định danh khách để tính giới hạn mua/khách Flash Sale — ưu tiên user_id
  -- (đăng nhập), khách vãng lai dùng SĐT (đơn hàng luôn bắt buộc nhập SĐT).
  v_customer_key := coalesce(new.user_id::text, lower(btrim(new.customer_phone)));

  -- 1) Tính lại giá THẬT từng sản phẩm từ bảng products, bỏ qua mọi price
  --    client gửi lên. Sản phẩm không tồn tại/đã ẩn (is_active=false) hoặc
  --    số lượng không hợp lệ sẽ bị loại khỏi đơn (không huỷ cả đơn). Hộp quà
  --    tặng/topping giờ là sản phẩm thật trong products, tự tính giá qua đây
  --    như mọi sản phẩm khác — không còn hậu tố "-gift" hay phụ phí cố định.
  --    "for update" khoá dòng sản phẩm khi đọc stock — tránh 2 đơn đặt cùng
  --    lúc cùng đọc được số tồn kho cũ, cả 2 đều tưởng đủ hàng rồi cùng qua.
  for item in select * from jsonb_array_elements(coalesce(new.items, '[]'::jsonb))
  loop
    clean_id := coalesce(item->>'id', '');
    qty      := coalesce((item->>'qty')::integer, 0);
    fs_item_id := nullif(item->>'flashSaleItemId', '');
    fs_applied := false;

    if qty <= 0 or clean_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      continue;
    end if;

    select price, stock into unit_price, live_stock from public.products
      where id = clean_id::uuid and is_active = true
      for update;
    if unit_price is null then
      continue; -- sản phẩm không tồn tại hoặc đã ẩn → bỏ qua item này
    end if;
    if live_stock < qty then
      -- SQLSTATE riêng (tiền tố STK, không trùng/dễ nhầm với order_code dạng
      -- "YD..." hay mã voucher) để client phân biệt CHÍNH XÁC đây là lỗi hết
      -- hàng cố ý chặn — không dựa vào so khớp nội dung message (dễ vỡ nếu
      -- đổi câu chữ sau này). Xem dat-hang.html.
      raise exception 'Sản phẩm "%" không đủ hàng (còn %, cần %)', item->>'name', live_stock, qty
        using errcode = 'STK01';
    end if;

    -- ── Flash Sale: nếu item có flashSaleItemId hợp lệ, xác thực + áp giá sale ──
    -- Malformed/không phải UUID → coi như KHÔNG có flash sale (fallback giá
    -- thật, không chặn đơn vì lỗi định dạng phía client không phải lỗi khách).
    if fs_item_id is not null and fs_item_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select fsi.id, fsi.product_id, fsi.sale_price, fsi.stock_limit, fsi.sold_count,
             fsi.per_customer_limit, fs.start_at as sess_start, fs.end_at as sess_end,
             fs.is_active as sess_active
        into fs_row
        from public.flash_sale_items fsi
        join public.flash_sales fs on fs.id = fsi.flash_sale_id
        where fsi.id = fs_item_id::uuid
        for update of fsi;

      if fs_row.id is null then
        raise exception 'Suất Flash Sale cho sản phẩm "%" không còn tồn tại', item->>'name'
          using errcode = 'FS01';
      end if;
      if fs_row.product_id <> clean_id::uuid then
        -- Cố tình gắn flashSaleItemId của sản phẩm khác vào để hưởng giá rẻ hơn.
        raise exception 'Suất Flash Sale không khớp sản phẩm "%"', item->>'name'
          using errcode = 'FS01';
      end if;
      if not fs_row.sess_active or now() < fs_row.sess_start or now() > fs_row.sess_end then
        raise exception 'Đợt Flash Sale cho sản phẩm "%" đã kết thúc hoặc chưa bắt đầu', item->>'name'
          using errcode = 'FS01';
      end if;
      if fs_row.sold_count + qty > fs_row.stock_limit then
        raise exception 'Sản phẩm "%" trong Flash Sale đã hết suất', item->>'name'
          using errcode = 'FS01';
      end if;
      if fs_row.per_customer_limit is not null then
        select coalesce(sum(qty), 0) into fs_used from public.flash_sale_purchases
          where flash_sale_item_id = fs_row.id and customer_key = v_customer_key;
        if fs_used + qty > fs_row.per_customer_limit then
          raise exception 'Bạn đã đạt giới hạn mua sản phẩm "%" trong đợt Flash Sale này', item->>'name'
            using errcode = 'FS01';
        end if;
      end if;

      -- Mọi kiểm tra qua: áp giá sale, cộng suất đã bán, ghi nhận lượt mua.
      unit_price := fs_row.sale_price;
      update public.flash_sale_items set sold_count = sold_count + qty where id = fs_row.id;
      insert into public.flash_sale_purchases (flash_sale_item_id, customer_key, qty)
        values (fs_row.id, v_customer_key, qty);
      fs_applied := true;
    end if;

    new_items := new_items || jsonb_build_object(
      'id', item->>'id',
      'productId', clean_id,
      'name', item->>'name',
      'image', item->>'image',
      'qty', qty,
      'price', unit_price,
      'oldPrice', item->'oldPrice',
      'isGiftBox', coalesce(item->'isGiftBox', 'false'::jsonb),
      'isTopping', coalesce(item->'isTopping', 'false'::jsonb),
      'flashSaleItemId', case when fs_applied then to_jsonb(fs_row.id) else 'null'::jsonb end
    );
    subtotal   := subtotal + unit_price * qty;
    item_count := item_count + qty;
  end loop;

  if item_count = 0 then
    raise exception 'Đơn hàng không có sản phẩm hợp lệ'
      using errcode = 'STK02';
  end if;

  new.items := new_items;

  -- 2) Tính lại voucher THẬT (nếu có) — không tin discount_amount client gửi.
  --    Đúng logic đã có ở dat-hang.html: kiểm tra active/thời hạn/min_order/
  --    apply_scope/giới hạn lượt dùng, nếu không còn hợp lệ thì bỏ voucher.
  if new.voucher_code is not null then
    select * into v from public.vouchers where code = new.voucher_code;

    if v.id is not null
       and v.is_active
       and v.apply_scope <> 'vip' -- 'vip' chưa có logic kiểm tra thật, chặn như client
       and (v.start_date is null or v.start_date <= now())
       and (v.end_date is null or v.end_date >= now())
    then
      -- Phạm vi áp dụng: 'products' chỉ tính trên các SP thuộc apply_product_ids
      if v.apply_scope = 'products' then
        select coalesce(sum((e->>'price')::bigint * (e->>'qty')::integer), 0) into eligible
          from jsonb_array_elements(new_items) e
          where (e->>'productId')::uuid = any(coalesce(v.apply_product_ids, '{}'));
      else
        eligible := subtotal;
      end if;

      if v.apply_scope = 'new_customer' then
        select count(*) into prior_orders from public.orders
          where user_id = new.user_id and status <> 'cancelled';
        if prior_orders > 0 then eligible := 0; end if;
      end if;

      if eligible > 0 and (v.min_order = 0 or subtotal >= v.min_order) then
        select count(*) into total_used from public.orders
          where voucher_code = v.code and status <> 'cancelled';
        select count(*) into my_used from public.orders
          where voucher_code = v.code and user_id = new.user_id and status <> 'cancelled';

        if total_used < coalesce(v.total_quantity, 1) and my_used < coalesce(v.max_uses_per_customer, 1) then
          discount := case when v.discount_type = 'percent'
            then round(eligible * v.discount_value / 100.0)
            else least(v.discount_value, eligible)
          end;
          voucher_ok := true;
        end if;
      end if;
    end if;
  end if;

  if not voucher_ok then
    new.voucher_code := null;
    discount := 0;
  end if;
  new.discount_amount := discount;

  -- 3) Tính lại phí ship theo đúng ngưỡng nghiệp vụ (nguồn chân lý duy nhất
  --    giờ nằm ở đây, không còn phụ thuộc số client gửi).
  ship_fee := case when subtotal >= free_ship_at then 0 else flat_ship_fee end;
  new.shipping_fee := ship_fee;

  -- 4) Chốt tổng tiền cuối cùng — ghi đè mọi giá trị client gửi lên.
  new.total_amount := greatest(subtotal - discount + ship_fee, 0);

  return new;
end;
$$;

-- Trigger cũ (sql/add-order-price-validation.sql) đã trỏ vào đúng hàm này —
-- CREATE OR REPLACE ở trên là đủ, không cần tạo lại trigger.
drop trigger if exists trg_validate_order_price on public.orders;
create trigger trg_validate_order_price
  before insert on public.orders
  for each row execute function public.validate_order_price();


-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    - Tạo 1 đợt flash_sales + 1 flash_sale_items qua admin/flash-sale.html.
--    - Trang chủ: đặt mua sản phẩm đó với đúng flashSaleItemId → đơn tạo
--      thành công, giá trong đơn = sale_price, flash_sale_items.sold_count
--      tăng đúng số lượng.
--    - Đặt vượt số suất còn lại (stock_limit) → lỗi mã FS01, đơn KHÔNG tạo.
--    - Đặt vượt giới hạn mua/khách (per_customer_limit) → lỗi mã FS01.
--    - Đặt sau end_at hoặc trước start_at → lỗi mã FS01.
--    - Đơn hàng KHÔNG kèm flashSaleItemId vẫn hoạt động bình thường như cũ
--      (giá thật từ products, không đụng gì tới Flash Sale).
-- ============================================================
