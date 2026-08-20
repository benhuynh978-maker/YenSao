-- ============================================================
--  HÀM TRỪ TỒN KHO — gọi ngay khi đặt hàng thành công
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ tạo/thay hàm (CREATE OR REPLACE), không đụng dữ liệu.
--
--  Dùng "greatest(stock - p_qty, 0)" để tồn kho không bao giờ
--  bị âm dù có lỡ trừ 2 lần hoặc trừ nhiều hơn số đang có.
--  Chỉ cấp quyền gọi hàm cho "authenticated" (đã đăng nhập) —
--  khớp với việc đặt hàng vốn đã bắt buộc đăng nhập.
-- ============================================================

create or replace function public.decrement_product_stock(p_id uuid, p_qty integer)
returns void
language sql
security definer
set search_path = public
as $$
  update public.products
  set stock = greatest(stock - p_qty, 0)
  where id = p_id;
$$;

-- Postgres tự động cấp EXECUTE cho PUBLIC (mọi vai trò, kể cả anon) khi tạo hàm mới —
-- phải thu hồi lại trước rồi mới cấp đúng cho authenticated, nếu không ai cũng gọi được.
revoke execute on function public.decrement_product_stock(uuid, integer) from public;
grant execute on function public.decrement_product_stock(uuid, integer) to authenticated;
