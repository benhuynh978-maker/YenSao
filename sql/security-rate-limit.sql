-- ============================================================
--  RATE-LIMIT DÙNG CHUNG TOÀN SITE (đăng nhập sai, liên hệ,
--  đánh giá, đặt hàng, áp mã giảm giá) + trần tổng chống lạm
--  dụng dồn nhiều loại hành động cùng lúc.
-- ------------------------------------------------------------
--  Toàn bộ ngưỡng/thuật toán nằm trong schema riêng `security`,
--  KHÔNG public qua Supabase Data API (chỉ schema `public` được
--  "Exposed" theo mặc định) — client chỉ gọi được qua hàm
--  public.check_rate_limit(), không đọc được ngưỡng hay log.
--
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: không đụng bảng/dữ liệu nào có sẵn.
--  Xem CLAUDE.md mục "Kiến trúc bảo mật" trước khi sửa file này.
-- ============================================================

create schema if not exists security;

create table if not exists security.rate_limit_config (
  bucket text primary key,
  max_count int not null,
  window_minutes int not null
);

create table if not exists security.rate_limit_log (
  id bigint generated always as identity primary key,
  bucket text not null,
  identifier text not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_rate_limit_log_lookup
  on security.rate_limit_log (bucket, identifier, created_at);

-- Ngưỡng khởi tạo — rộng rãi để khách thật không gặp phiền,
-- đủ chặn dò/spam máy móc. Đổi số ở đây bất cứ lúc nào (UPDATE),
-- không cần sửa code HTML/JS.
insert into security.rate_limit_config (bucket, max_count, window_minutes) values
  ('login_fail',     5,  15),
  ('contact_form',   5,  60),
  ('review_submit',  5,  60),
  ('order_place',    8,  60),
  ('voucher_apply',  10, 10),
  ('global_write',   30, 60)
on conflict (bucket) do nothing;

-- Hàm kiểm tra + ghi nhận. security definer để đọc/ghi được bảng
-- trong schema security dù người gọi (anon/authenticated) không
-- có quyền trực tiếp trên schema đó.
create or replace function public.check_rate_limit(p_bucket text, p_identifier text)
returns boolean
language plpgsql
security definer
set search_path = security, public
as $$
declare
  v_cfg          security.rate_limit_config;
  v_count        int;
  v_global       security.rate_limit_config;
  v_global_count int;
begin
  if p_bucket is null or p_identifier is null or length(p_identifier) = 0 then
    return true; -- thiếu dữ liệu thì không chặn (tránh tự khoá site vì gọi sai)
  end if;

  select * into v_cfg from security.rate_limit_config where bucket = p_bucket;
  if v_cfg is null then
    return true; -- bucket chưa đăng ký thì không chặn
  end if;

  select count(*) into v_count
  from security.rate_limit_log
  where bucket = p_bucket
    and identifier = p_identifier
    and created_at > now() - (v_cfg.window_minutes || ' minutes')::interval;

  if v_count >= v_cfg.max_count then
    return false;
  end if;

  -- Trần tổng: chặn kiểu lách bằng cách dồn nhiều loại hành động khác
  -- nhau (mỗi loại dưới ngưỡng riêng) cộng lại thành lạm dụng.
  select * into v_global from security.rate_limit_config where bucket = 'global_write';
  if v_global is not null then
    select count(*) into v_global_count
    from security.rate_limit_log
    where identifier = p_identifier
      and created_at > now() - (v_global.window_minutes || ' minutes')::interval;

    if v_global_count >= v_global.max_count then
      return false;
    end if;
  end if;

  insert into security.rate_limit_log (bucket, identifier) values (p_bucket, p_identifier);

  -- Dọn log cũ ngẫu nhiên (1% mỗi lần gọi) để bảng không phình to dần —
  -- không cần pg_cron/hạ tầng thêm.
  if random() < 0.01 then
    delete from security.rate_limit_log where created_at < now() - interval '2 days';
  end if;

  return true;
end;
$$;

revoke all on function public.check_rate_limit(text, text) from public;
grant execute on function public.check_rate_limit(text, text) to anon, authenticated;

-- Chặn mọi đường truy cập trực tiếp vào schema security dù ai cố tình
-- gọi thẳng qua REST (bình thường PostgREST đã không thấy schema này
-- vì không nằm trong "Exposed schemas", đây là lớp phòng thủ thêm).
revoke all on schema security from anon, authenticated, public;
revoke all on all tables in schema security from anon, authenticated, public;
