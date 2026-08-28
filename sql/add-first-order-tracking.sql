-- ============================================================
--  first_order_at — mốc đơn hàng ĐẦU TIÊN của mỗi khách, lưu thành cột
--  thật trong profiles. Dùng để admin/dashboard.html tính "Khách hàng
--  mới" mà KHÔNG cần quét toàn bộ bảng orders mỗi lần mở trang (trước
--  đây tải hết orders không phân trang, có thể bị Supabase "Max Rows"
--  cắt bớt âm thầm khi đơn hàng tăng nhiều — tính sai số khách mới mà
--  không báo lỗi gì).
--
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột/hàm/trigger, chạy lại nhiều lần không lỗi.
--
--  Cùng khuôn mẫu với sql/add-customer-tier.sql: set 1 LẦN DUY NHẤT lúc
--  có đơn đầu tiên (không cần quét lại theo cron như customer_tier, vì
--  mốc "đơn đầu tiên" không đổi theo thời gian trôi qua). Tính CẢ đơn đã
--  hủy (giống quy tắc đếm "tổng số đơn" của customer_tier) — 1 khách đặt
--  rồi hủy vẫn tính là đã từng ghé mua, không phải chưa từng đặt.
-- ============================================================

alter table public.profiles add column if not exists first_order_at timestamptz;

-- ── Backfill 1 lần cho khách đã có đơn từ trước khi cột này tồn tại ──
update public.profiles p
set first_order_at = sub.min_created
from (
  select user_id, min(created_at) as min_created
  from public.orders
  where user_id is not null
  group by user_id
) sub
where p.id = sub.user_id and p.first_order_at is null;

-- ── Trigger: đơn mới của user_id chưa có first_order_at → set ngay ──
create or replace function public.trg_set_first_order_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is not null then
    update public.profiles
    set first_order_at = new.created_at
    where id = new.user_id and first_order_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_set_first_order_at on public.orders;
create trigger trg_orders_set_first_order_at
  after insert on public.orders
  for each row execute function public.trg_set_first_order_at();
