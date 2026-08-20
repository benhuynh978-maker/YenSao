-- ============================================================
--  VÁ LỖ HỔNG NGHIÊM TRỌNG — giá tiền đơn hàng (total_amount,
--  discount_amount, shipping_fee, giá từng sản phẩm trong items)
--  trước đây do CLIENT tự tính rồi gửi thẳng lên, RLS chỉ kiểm
--  tra user_id chứ không kiểm tra số tiền → khách có thể sửa
--  request (DevTools/Network) để đặt giá tuỳ ý, đơn vẫn insert
--  thành công và vẫn bị trừ tồn kho như đơn thật.
-- ------------------------------------------------------------
--  CÁCH VÁ: trigger BEFORE INSERT tự tính lại TOÀN BỘ giá tiền
--  từ dữ liệu thật trong products/vouchers, GHI ĐÈ lên mọi giá
--  trị client gửi lên — giống hệt cách dự án đã vá lỗ hổng tồn
--  kho trước đây (xem trigger handle_new_order_stock trong
--  sql/add-product-popularity.sql). Không cần sửa dat-hang.html.
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ tạo/thay hàm + trigger, không đụng dữ liệu cũ.
-- ============================================================

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
begin
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

    -- isGiftBox/isTopping chỉ là cờ HIỂN THỊ (gắn nhãn "hộp quà"/"topping"
    -- ở trang chi tiết đơn), không được validate lại ở đây — không ảnh hưởng
    -- giá/tồn kho vì unit_price luôn tính từ products.price theo id thật.
    new_items := new_items || jsonb_build_object(
      'id', item->>'id',
      'productId', clean_id,
      'name', item->>'name',
      'image', item->>'image',
      'qty', qty,
      'price', unit_price,
      'oldPrice', item->'oldPrice',
      'isGiftBox', coalesce(item->'isGiftBox', 'false'::jsonb),
      'isTopping', coalesce(item->'isTopping', 'false'::jsonb)
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

drop trigger if exists trg_validate_order_price on public.orders;
create trigger trg_validate_order_price
  before insert on public.orders
  for each row execute function public.validate_order_price();
