-- ============================================================
--  NHÓM KHÁCH HÀNG (customer_tier) — VIP / Mới / Thường xuyên /
--  Có nguy cơ rời — lưu thành cột thật trong profiles.
-- ------------------------------------------------------------
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột/hàm, chạy lại nhiều lần không lỗi.
--
--  QUY TẮC (đã chốt 11/07/2026), ưu tiên xét theo thứ tự — khớp
--  điều kiện nào trước thì dừng ở đó:
--   1) Có nguy cơ rời: quá 30 ngày kể từ đơn gần nhất (ĐÈ LÊN mọi
--      hạng khác, kể cả đang là VIP).
--   2) VIP: từ 3 đơn KHÔNG HỦY trở lên TRONG THÁNG HIỆN TẠI, VÀ
--      tổng chi tiêu (không hủy, tính từ trước tới giờ) ≥ 10 triệu.
--      Lưu ý: vì tính theo tháng hiện tại nên đầu tháng mới, khách
--      VIP tháng trước sẽ tạm về Thường xuyên cho tới khi đủ lại
--      3 đơn trong tháng mới — đã xác nhận đúng ý muốn.
--   3) Mới: tổng số đơn (kể cả đơn đã hủy) dưới 3. Mặc định mọi
--      tài khoản mới tạo đều là 'new' (cột có default), không cần
--      chờ có đơn mới gắn nhãn.
--   4) Thường xuyên: còn lại.
--
--  VÌ SAO CẦN CHẠY ĐỊNH KỲ (không chỉ trigger theo đơn hàng):
--  "Có nguy cơ rời" (mốc 30 ngày) và mốc "đầu tháng mới" của VIP
--  đều đổi theo THỜI GIAN TRÔI QUA, không phải theo sự kiện đặt
--  đơn — nếu chỉ có trigger, 1 khách im lặng > 30 ngày sẽ bị "đơ"
--  ở nhãn cũ vì không có đơn mới nào kích hoạt tính lại. Vì vậy
--  cần thêm 1 tác vụ pg_cron chạy mỗi ngày để quét lại toàn bộ.
-- ============================================================

alter table public.profiles add column if not exists customer_tier text not null default 'new';

-- ── Hàm tính lại tier cho 1 khách hàng ─────────────────────────
create or replace function public.recompute_customer_tier(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last_order   timestamptz;
  v_month_count  int;
  v_total_revenue bigint;
  v_total_orders int;
  v_tier         text;
begin
  select max(created_at) into v_last_order from public.orders where user_id = p_user_id;
  if v_last_order is null then
    return; -- chưa có đơn nào — giữ nguyên mặc định 'new', không đụng vào
  end if;

  select count(*) into v_month_count from public.orders
    where user_id = p_user_id and status <> 'cancelled'
    and date_trunc('month', created_at) = date_trunc('month', now());

  select coalesce(sum(total_amount), 0) into v_total_revenue from public.orders
    where user_id = p_user_id and status <> 'cancelled';

  select count(*) into v_total_orders from public.orders where user_id = p_user_id;

  if (now() - v_last_order) > interval '30 days' then
    v_tier := 'churn';
  elsif v_month_count >= 3 and v_total_revenue >= 10000000 then
    v_tier := 'vip';
  elsif v_total_orders < 3 then
    v_tier := 'new';
  else
    v_tier := 'regular';
  end if;

  update public.profiles set customer_tier = v_tier where id = p_user_id;
end;
$$;

-- ── Trigger: có đơn mới hoặc đơn đổi trạng thái → tính lại ngay ──
create or replace function public.trg_recompute_tier_on_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.user_id is not null then
    perform public.recompute_customer_tier(new.user_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_recompute_tier on public.orders;
create trigger trg_orders_recompute_tier
  after insert or update on public.orders
  for each row execute function public.trg_recompute_tier_on_order();

-- ── pg_cron: quét lại TOÀN BỘ khách hàng mỗi ngày lúc 2h sáng giờ VN ──
-- (02:00 GMT+7 = 19:00 UTC ngày hôm trước — giờ vắng khách, ít ảnh hưởng)
-- Nếu lệnh "create extension" bên dưới báo lỗi thiếu quyền: vào Supabase
-- Dashboard → Database → Extensions → bật "pg_cron" bằng tay rồi chạy lại
-- phần pg_cron này của file (phần alter/create function ở trên đã chạy
-- xong rồi thì không cần chạy lại).
create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'recompute-customer-tiers-daily') then
    perform cron.unschedule('recompute-customer-tiers-daily');
  end if;
end $$;

select cron.schedule(
  'recompute-customer-tiers-daily',
  '0 19 * * *',
  $$
    select public.recompute_customer_tier(id)
    from public.profiles
    where id in (select distinct user_id from public.orders where user_id is not null);
  $$
);
