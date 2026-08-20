-- ============================================================
--  "PHỔ BIẾN NHẤT" — sold_count (lượt bán) + view_count (lượt xem)
--  Gộp chung với Mục 4 (bảo mật, tạm hoãn trước đó): sửa tận gốc
--  cách trừ tồn kho — chuyển từ RPC công khai (ai có tài khoản
--  cũng gọi được, không kiểm tra hợp lệ, có thể bị lợi dụng tăng/
--  phá tồn kho) sang TRIGGER tự động chạy khi có đơn hàng THẬT.
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột/hàm, không xóa dữ liệu. Chạy lại nhiều
--  lần không lỗi (CREATE OR REPLACE / IF NOT EXISTS).
--  Cần đã chạy sql/security-rate-limit.sql trước đó (bucket mới
--  ở cuối file này ghi vào schema `security` đã tạo ở đó).
-- ============================================================

alter table public.products add column if not exists sold_count integer not null default 0;
alter table public.products add column if not exists view_count integer not null default 0;

-- ── Trigger: có đơn hàng mới → tự trừ tồn kho + cộng sold_count ──
-- Đọc thẳng cột items (jsonb) vừa insert — không còn API nào gọi rời
-- được nữa. Mỗi sản phẩm trong đơn xử lý riêng trong khối BEGIN/EXCEPTION
-- — 1 sản phẩm lỗi (id/qty bất thường) không làm hỏng cả đơn hàng.
create or replace function public.handle_new_order_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  clean_id text;
  qty integer;
begin
  for item in select * from jsonb_array_elements(coalesce(new.items, '[]'::jsonb))
  loop
    begin
      clean_id := coalesce(item->>'id', '');
      qty := coalesce((item->>'qty')::integer, 1);
      if qty > 0 and clean_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
        update public.products
        set stock = greatest(stock - qty, 0),
            sold_count = sold_count + qty
        where id = clean_id::uuid;
      end if;
    exception when others then
      null; -- bỏ qua item lỗi, không hủy cả đơn hàng
    end;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_new_order_stock on public.orders;
create trigger trg_new_order_stock
  after insert on public.orders
  for each row execute function public.handle_new_order_stock();

-- Không còn cần gọi trừ tồn kho từ client nữa — thu hồi quyền gọi API
-- (giữ nguyên định nghĩa hàm phòng khi cần chạy tay qua SQL Editor).
revoke execute on function public.decrement_product_stock(uuid, integer) from authenticated;
revoke execute on function public.decrement_product_stock(uuid, integer) from anon;

-- ── RPC: tăng lượt xem trang chi tiết sản phẩm ──
-- Rate-limit thật xử lý ở client qua SecurityGate.check('product_view', ...)
-- trước khi gọi — vượt ngưỡng thì bỏ qua gọi RPC này (trang vẫn hiển thị
-- bình thường), không có gì chặn ở tầng DB (đúng nguyên tắc fail-open).
create or replace function public.increment_product_view(p_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.products set view_count = view_count + 1 where id = p_id;
$$;
revoke execute on function public.increment_product_view(uuid) from public;
grant execute on function public.increment_product_view(uuid) to anon, authenticated;

-- ── Đăng ký bucket rate-limit mới cho lượt xem ──
insert into security.rate_limit_config (bucket, max_count, window_minutes) values
  ('product_view', 60, 60)
on conflict (bucket) do nothing;
