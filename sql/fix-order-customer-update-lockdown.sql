-- ============================================================
--  VÁ LỖ HỔNG P2-3 — KHÁCH TỰ SỬA MỌI CỘT ĐƠN CỦA MÌNH SAU KHI ĐẶT
-- ------------------------------------------------------------
--  ĐÃ KIỂM CHỨNG LIVE (15/07/2026): khách thường gọi REST PATCH đơn
--  của chính mình đổi status='delivered' + total_amount=0 → THÀNH CÔNG.
--  Vì policy orders_update_own (fix-orders-rls-v2.sql) chỉ kiểm CHỦ đơn
--  (auth.uid()=user_id), KHÔNG kiểm được đổi cột nào; trigger giá
--  validate_order_price chỉ chạy BEFORE INSERT, không chạy khi UPDATE.
--
--  RLS không giải quyết được vì WITH CHECK không so sánh OLD vs NEW.
--  Cách đúng: trigger BEFORE UPDATE (giống protect_profile_role của P0-2).
--
--  QUY TẮC: khách CHỈ được HỦY đơn đang 'pending' của mình (đúng hành vi
--  duy nhất mà UI cho phép — cancelOrder ở don-hang-cua-toi.html). Mọi
--  cột khác bị ép về giá trị CŨ (whitelist: new:=old rồi mới mở đúng 1
--  hành vi → thêm cột mới sau này TỰ an toàn, không cần liệt kê từng cột).
--  Admin (is_admin) và SQL Editor/service_role (auth.uid null) toàn quyền.
--
--  CÁCH DÙNG: Supabase → SQL Editor → New query → dán TOÀN BỘ → Run.
--  AN TOÀN: chỉ thêm hàm + trigger, không đụng dữ liệu. Chạy lại nhiều
--  lần vẫn an toàn (create or replace + drop trigger if exists).
--  Xem CLAUDE.md mục "Kiến trúc bảo mật" (#4, #5).
-- ============================================================

create or replace function public.protect_order_customer_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  wants_cancel boolean := (new.status = 'cancelled');
begin
  -- Admin: toàn quyền sửa đơn (admin/don-hang.html đổi trạng thái, vận đơn...).
  if public.is_admin() then
    return new;
  end if;
  -- Không đăng nhập (SQL Editor / service_role): bỏ qua để còn sửa/khôi phục tay.
  if auth.uid() is null then
    return new;
  end if;

  -- Khách thường: ép TẤT CẢ cột về giá trị cũ trước.
  new := old;
  -- Chỉ mở đúng 1 hành vi: hủy đơn đang 'pending' của chính mình.
  if wants_cancel and old.status = 'pending' then
    new.status       := 'cancelled';
    new.cancelled_by := 'customer';
    new.updated_at   := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_order_customer_update on public.orders;
create trigger trg_protect_order_customer_update
  before update on public.orders
  for each row execute function public.protect_order_customer_update();

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY:
--    (a) KHÁCH thường (Console trang Đơn hàng của tôi):
--        sb.from('orders').update({status:'delivered',total_amount:0})
--          .eq('id', <đơn của bạn>).select('id,status,total_amount')
--        → đọc lại thấy status/total KHÔNG đổi (bị trả về cũ). ĐÃ CHẶN.
--    (b) KHÁCH bấm "Hủy" 1 đơn đang 'pending' qua UI → VẪN hủy được.
--    (c) KHÁCH thử hủy đơn KHÔNG phải 'pending' (vd 'delivered') qua REST
--        → không đổi (UI vốn đã ẩn nút, REST giờ cũng chặn).
--    (d) ADMIN (admin/don-hang.html) đổi trạng thái / vận đơn → VẪN chạy.
--
--  KHÔI PHỤC đơn đã bị test giả mạo (chạy trong SQL Editor — auth.uid null
--  nên trigger bỏ qua): điền lại đúng status + total gốc, ví dụ:
--    update public.orders
--       set status='pending', total_amount=<số tiền gốc>
--     where id=8;
--  (hoặc dùng admin/don-hang.html sửa lại — admin bỏ qua trigger.)
-- ============================================================
