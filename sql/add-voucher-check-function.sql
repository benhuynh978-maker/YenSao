-- ============================================================
--  VÁ LỖ HỔNG P1-1 — LỘ TOÀN BỘ MÃ VOUCHER CHO NGƯỜI LẠ
--  GIAI ĐOẠN 1/3: tạo hàm kiểm mã (RPC), CHƯA khóa bảng.
-- ------------------------------------------------------------
--  ĐÃ KIỂM CHỨNG LIVE (14/07/2026): anon gọi REST đọc được TOÀN BỘ
--  bảng vouchers (mọi mã + % giảm + giới hạn lượt). Không thể chặn
--  bằng RLS (RLS không ép "chỉ đọc nếu biết đúng mã"). Cách đúng:
--  KHÔNG cho client đọc bảng, thay bằng hàm kiểm 1 mã cụ thể.
--
--  Hàm này chạy SECURITY DEFINER — mirror ĐÚNG logic kiểm mã trong
--  trigger validate_order_price (sql/add-order-price-validation.sql):
--  existence → active → thời hạn → không 'vip' → khách-mới → giới hạn
--  lượt (tổng + mỗi khách). Phần min_order/eligible/discount vẫn để
--  CLIENT tính xem-trước (đổi theo giỏ hàng), trigger mới chốt thật.
--d
--  QUAN TRỌNG: phần đếm lượt (total_used/my_used) BẮT BUỘC nằm ở đây
--  vì sau P0-1, anon/authenticated không đọc được toàn bộ orders nữa —
--  chỉ hàm definer này mới đếm đúng tổng lượt dùng của mọi khách.
--
--  GIAI ĐOẠN NÀY AN TOÀN: chỉ THÊM hàm, KHÔNG revoke/không đổi policy,
--  không sửa client → mọi thứ cũ vẫn chạy song song. Khóa bảng + đổi
--  client làm ở Giai đoạn 2 & 3 sau khi verify hàm này chạy đúng.
--
--  CÁCH DÙNG: Supabase → SQL Editor → New query → dán TOÀN BỘ → Run.
--  Xem CLAUDE.md mục "Kiến trúc bảo mật".
-- ============================================================

create or replace function public.check_voucher(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v            public.vouchers;
  uid         uuid := auth.uid();
  total_used  int;
  my_used     int;
  prior_orders int;
begin
  if p_code is null or length(btrim(p_code)) = 0 then
    return jsonb_build_object('ok', false, 'reason', 'Vui lòng nhập mã giảm giá');
  end if;

  select * into v from public.vouchers where code = p_code;
  if v.id is null then
    return jsonb_build_object('ok', false, 'reason', 'Mã giảm giá không tồn tại');
  end if;
  if not v.is_active then
    return jsonb_build_object('ok', false, 'reason', 'Mã giảm giá đã bị tạm dừng');
  end if;
  if v.start_date is not null and v.start_date > now() then
    return jsonb_build_object('ok', false, 'reason', 'Mã giảm giá chưa đến ngày áp dụng');
  end if;
  if v.end_date is not null and v.end_date < now() then
    return jsonb_build_object('ok', false, 'reason', 'Mã giảm giá đã hết hạn');
  end if;
  if v.apply_scope = 'vip' then
    return jsonb_build_object('ok', false, 'reason', 'Mã này đang được hoàn thiện, chưa thể áp dụng');
  end if;

  -- Từ đây cần biết khách là ai (khách-mới + giới hạn lượt). Áp mã vốn bắt đăng nhập.
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'Vui lòng đăng nhập để dùng mã giảm giá');
  end if;

  if v.apply_scope = 'new_customer' then
    select count(*) into prior_orders from public.orders
      where user_id = uid and status <> 'cancelled';
    if prior_orders > 0 then
      return jsonb_build_object('ok', false, 'reason', 'Mã này chỉ áp dụng cho đơn hàng đầu tiên');
    end if;
  end if;

  select count(*) into total_used from public.orders
    where voucher_code = v.code and status <> 'cancelled';
  if total_used >= coalesce(v.total_quantity, 1) then
    return jsonb_build_object('ok', false, 'reason', 'Mã giảm giá đã hết lượt sử dụng');
  end if;

  select count(*) into my_used from public.orders
    where voucher_code = v.code and user_id = uid and status <> 'cancelled';
  if my_used >= coalesce(v.max_uses_per_customer, 1) then
    return jsonb_build_object('ok', false, 'reason', 'Bạn đã dùng hết lượt cho mã này');
  end if;

  -- Hợp lệ → trả CHI TIẾT để client tính min_order/eligible/discount xem trước.
  -- (Không lộ mã nào khác vì khách phải gửi ĐÚNG 1 mã cụ thể mới có kết quả.)
  return jsonb_build_object(
    'ok', true,
    'code', v.code,
    'discount_type', v.discount_type,
    'discount_value', v.discount_value,
    'min_order', v.min_order,
    'apply_scope', v.apply_scope,
    'apply_product_ids', to_jsonb(coalesce(v.apply_product_ids, '{}'::uuid[]))
  );
end;
$$;

-- Chỉ cho authenticated gọi (áp mã luôn cần đăng nhập). KHÔNG cho anon → chặn cả
-- việc dò thử từng mã khi chưa đăng nhập.
-- LƯU Ý (bài học decrement_product_stock): Supabase TỰ cấp EXECUTE cho anon RIÊNG
-- qua "default privileges" khi tạo hàm mới — nên phải revoke from anon RIÊNG, chứ
-- revoke from public KHÔNG đủ (anon vẫn gọi được, đã kiểm chứng 14/07/2026).
revoke execute on function public.check_voucher(text) from public;
revoke execute on function public.check_voucher(text) from anon;
grant execute on function public.check_voucher(text) to authenticated;

-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY (Giai đoạn 1):
--    - Đăng nhập 1 tài khoản, gọi rpc('check_voucher', {p_code:'<mã thật>'})
--      → trả {ok:true, code, discount_type, ...}.
--    - Mã sai → {ok:false, reason:'Mã giảm giá không tồn tại'}.
--    - Chưa đăng nhập gọi → bị chặn (không có quyền execute).
--  Bảng vouchers lúc này VẪN đọc được như cũ (chưa khóa) — client cũ chạy bình
--  thường song song. Sang Giai đoạn 2 (đổi client) rồi Giai đoạn 3 (khóa bảng).
-- ============================================================
