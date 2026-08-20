-- ============================================================
--  VÁ LỖ HỔNG P0-2 — LEO THANG ĐẶC QUYỀN QUA cột profiles.role
-- ------------------------------------------------------------
--  ĐÃ CHỨNG MINH LIVE (14/07/2026): 1 tài khoản khách thường tự gọi
--    PATCH /rest/v1/profiles?id=eq.<chính mình>  body {"role":"admin"}
--  là role đổi customer→admin, sau đó đọc/sửa được toàn bộ dữ liệu
--  như admin (mọi đơn, mọi hồ sơ...). Nguyên nhân: policy update
--  profiles cho khách sửa hồ sơ của mình nhưng KHÔNG giới hạn cột,
--  và không có gì chặn đổi role.
--
--  CÁCH VÁ: trigger BEFORE UPDATE ép giữ nguyên role cũ nếu người
--  sửa là user API đã đăng nhập mà KHÔNG phải admin thật. Không đụng
--  policy (khách vẫn sửa được tên/avatar/SĐT bình thường).
--
--  CÁCH DÙNG: Supabase → SQL Editor → New query → dán TOÀN BỘ → Run.
--  AN TOÀN: chỉ tạo/thay hàm + trigger, KHÔNG đụng dữ liệu. Chạy lại
--           nhiều lần vẫn an toàn.
--  Xem CLAUDE.md mục "Kiến trúc bảo mật" (#4). Chỉ sửa vì lý do bảo mật.
-- ============================================================

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Chỉ can thiệp khi cột role BỊ ĐỔI.
  if new.role is distinct from old.role then
    -- Chặn khi người sửa là USER API đã đăng nhập (auth.uid() không null)
    -- mà KHÔNG phải admin thật → ép giữ nguyên role cũ.
    --
    -- auth.uid() IS NULL = ngữ cảnh backend đặc quyền (SQL Editor chạy dưới
    -- role postgres, hoặc service_role key) → CHO PHÉP đổi, để:
    --   (a) admin cấp quyền tay qua SQL Editor (SETUP-DATABASE.sql mục 9),
    --   (b) bootstrap admin ĐẦU TIÊN khi chưa có admin nào (is_admin() còn false).
    if auth.uid() is not null and not public.is_admin() then
      new.role := old.role;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profile_role on public.profiles;
create trigger trg_protect_profile_role
  before update on public.profiles
  for each row execute function public.protect_profile_role();

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    Đăng nhập 1 tài khoản khách thường rồi thử PATCH role='admin'
--    cho chính mình → role phải VẪN là 'customer' (trigger đã revert).
--    Admin thật đổi role (qua API khi đã là admin, hoặc qua SQL Editor)
--    vẫn hoạt động bình thường.
--
--  GHI CHÚ: bản vá này CHỈ bảo vệ cột role. Cột customer_tier CỐ Ý
--  KHÔNG khóa ở đây vì hàm recompute_customer_tier (add-customer-tier.sql)
--  chạy trong ngữ cảnh auth.uid() của khách — khóa sẽ làm hỏng cơ chế tự
--  tính hạng. Rủi ro khách tự sửa customer_tier là thấp (voucher scope
--  'vip' vốn đang chặn cứng) — xử lý sau cùng nhóm P2-3.
-- ============================================================
