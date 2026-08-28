-- ============================================================
--  BÁO CÁO CHO TRỢ LÝ AI QUẢN TRỊ — 4 hàm RPC chỉ-đọc
-- ------------------------------------------------------------
--  Phục vụ widget "Trợ lý kinh doanh" trên các trang admin
--  (js/admin-ai-chat.js). Xem kế hoạch đầy đủ ở
--  AI-Chat-Admin-Ke-Hoach.md tại thư mục gốc.
--
--  CÁCH DÙNG: dán TOÀN BỘ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ tạo/thay hàm (create or replace), KHÔNG đụng
--  bảng/dữ liệu/policy nào. Chạy lại nhiều lần không lỗi.
--
--  VÌ SAO TÍNH TRONG POSTGRES CHỨ KHÔNG TÍNH Ở CLIENT:
--  gom cả bảng orders về trình duyệt rồi cộng bằng JS sẽ bị
--  Supabase "Max Rows" cắt âm thầm khi đơn nhiều → báo cáo sai
--  mà KHÔNG báo lỗi (đúng lỗi đã gặp thật ở thẻ "Khách hàng mới"
--  của admin/dashboard.html, xem sql/add-first-order-tracking.sql).
--  Tính trong SQL thì không giới hạn dòng, trả về vài chục con số.
--
--  BẢO MẬT — BẮT BUỘC ĐỌC:
--  Cả 4 hàm đều `security definer` (chạy bằng quyền chủ hàm nên
--  BỎ QUA RLS). Vì vậy mỗi hàm PHẢI tự kiểm public.is_admin() ở
--  dòng đầu — thiếu bước này thì BẤT KỲ tài khoản khách nào đã
--  đăng nhập cũng gọi được và đọc sạch doanh thu/khách hàng.
--  (Cùng bài học đã ghi trong sql/add-list-pagination-functions.sql.)
--
--  QUY ƯỚC TÍNH TOÁN — thống nhất toàn bộ 4 báo cáo:
--   - Doanh thu = tổng total_amount của đơn KHÔNG huỷ
--     (khớp đúng sumRevenue() ở admin/dashboard.html).
--   - Số đơn thì tính CẢ đơn huỷ (để còn tính được tỉ lệ huỷ).
--   - Mọi mốc thời gian tính theo giờ Việt Nam (Asia/Ho_Chi_Minh),
--     KHÔNG dùng now() trần — now() là UTC, lệch 7 tiếng sẽ khiến
--     đơn đặt từ 0h–7h sáng bị tính nhầm sang "hôm qua".
-- ============================================================


-- ────────────────────────────────────────────────────────────
--  0a) Chuẩn hoá tên khoảng thời gian
--      Model AI có thể gửi giá trị sai chính tả/ngoài danh sách —
--      đưa về 'thang_nay' thay vì báo lỗi, tránh làm vỡ hội thoại.
-- ────────────────────────────────────────────────────────────
create or replace function public.admin_ai_chuan_khoang(p_khoang text)
returns text
language sql
immutable
as $$
  select case
    when p_khoang in ('hom_nay','hom_qua','7_ngay_qua','thang_nay','thang_truoc','toan_thoi_gian')
      then p_khoang
    else 'thang_nay'
  end;
$$;


-- ────────────────────────────────────────────────────────────
--  0b) Quy đổi tên khoảng → mốc thời gian thật (giờ Việt Nam)
--      Trả về cả kỳ TRƯỚC để báo cáo tự so sánh được, không bắt
--      AI gọi tool 2 lần rồi tự tính nhẩm (dễ sai + tốn token).
--      Quy ước kỳ trước: khoảng cùng độ dài liền kề ngay trước đó.
-- ────────────────────────────────────────────────────────────
create or replace function public.admin_ai_khoang(p_khoang text)
returns table (tu timestamptz, den timestamptz, tu_truoc timestamptz, den_truoc timestamptz)
language plpgsql
stable
as $$
declare
  TZ constant text := 'Asia/Ho_Chi_Minh';
  v_hom_nay   timestamp;   -- 0h hôm nay theo giờ VN (dạng "trần", chưa gắn múi giờ)
  v_dau_thang timestamp;
begin
  v_hom_nay   := date_trunc('day',   now() at time zone TZ);
  v_dau_thang := date_trunc('month', now() at time zone TZ);

  if p_khoang = 'hom_nay' then
    -- Kỳ trước = TRỌN ngày hôm qua (giống cách admin/dashboard.html
    -- đang so sánh hôm nay với hôm qua — giữ nhất quán với trang đó).
    tu        := v_hom_nay                    at time zone TZ;
    den       := now();
    tu_truoc  := (v_hom_nay - interval '1 day') at time zone TZ;
    den_truoc := v_hom_nay                    at time zone TZ;

  elsif p_khoang = 'hom_qua' then
    tu        := (v_hom_nay - interval '1 day') at time zone TZ;
    den       := v_hom_nay                      at time zone TZ;
    tu_truoc  := (v_hom_nay - interval '2 day') at time zone TZ;
    den_truoc := (v_hom_nay - interval '1 day') at time zone TZ;

  elsif p_khoang = '7_ngay_qua' then
    -- 7 ngày gồm cả hôm nay (hôm nay tính tới thời điểm hiện tại).
    tu        := (v_hom_nay - interval '6 day')  at time zone TZ;
    den       := now();
    tu_truoc  := (v_hom_nay - interval '13 day') at time zone TZ;
    den_truoc := (v_hom_nay - interval '6 day')  at time zone TZ;

  elsif p_khoang = 'thang_truoc' then
    tu        := (v_dau_thang - interval '1 month') at time zone TZ;
    den       := v_dau_thang                        at time zone TZ;
    tu_truoc  := (v_dau_thang - interval '2 month') at time zone TZ;
    den_truoc := (v_dau_thang - interval '1 month') at time zone TZ;

  elsif p_khoang = 'toan_thoi_gian' then
    tu        := '-infinity'::timestamptz;
    den       := now();
    tu_truoc  := null;   -- không có "kỳ trước" của toàn thời gian
    den_truoc := null;

  else  -- 'thang_nay' (và mọi giá trị lạ đã được chuẩn hoá về đây)
    tu        := v_dau_thang                        at time zone TZ;
    den       := now();
    tu_truoc  := (v_dau_thang - interval '1 month') at time zone TZ;
    den_truoc := v_dau_thang                        at time zone TZ;
  end if;

  return next;
end;
$$;


-- ────────────────────────────────────────────────────────────
--  0c) Tính % tăng/giảm — trả NULL khi kỳ trước bằng 0
--      (không bao giờ chia cho 0, và "tăng vô hạn" là vô nghĩa).
-- ────────────────────────────────────────────────────────────
create or replace function public.admin_ai_phan_tram(p_nay numeric, p_truoc numeric)
returns numeric
language sql
immutable
as $$
  select case
    when p_truoc is null or p_truoc = 0 then null
    else round((p_nay - p_truoc) * 100.0 / p_truoc, 1)
  end;
$$;


-- ════════════════════════════════════════════════════════════
--  1) BÁO CÁO KINH DOANH — doanh thu / đơn hàng / tỉ lệ huỷ
-- ════════════════════════════════════════════════════════════
create or replace function public.admin_bao_cao_kinh_doanh(p_khoang text default 'thang_nay')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  k              record;
  v_khoang       text;
  v_doanh_thu    bigint;
  v_so_don       integer;
  v_so_don_ok    integer;   -- đơn không huỷ (để tính giá trị đơn trung bình)
  v_so_don_huy   integer;
  v_dt_truoc     bigint;
  v_don_truoc    integer;
  v_trang_thai   jsonb;
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem báo cáo này.';
  end if;

  v_khoang := public.admin_ai_chuan_khoang(p_khoang);
  select * into k from public.admin_ai_khoang(v_khoang);

  -- Kỳ hiện tại
  select coalesce(sum(total_amount) filter (where status <> 'cancelled'), 0),
         count(*),
         count(*) filter (where status <> 'cancelled'),
         count(*) filter (where status =  'cancelled')
    into v_doanh_thu, v_so_don, v_so_don_ok, v_so_don_huy
  from public.orders
  where created_at >= k.tu and created_at < k.den;

  -- Số đơn theo từng trạng thái
  select coalesce(jsonb_object_agg(status, so_luong), '{}'::jsonb)
    into v_trang_thai
  from (
    select status, count(*) as so_luong
    from public.orders
    where created_at >= k.tu and created_at < k.den
    group by status
  ) t;

  -- Kỳ trước (nếu có)
  if k.tu_truoc is not null then
    select coalesce(sum(total_amount) filter (where status <> 'cancelled'), 0),
           count(*)
      into v_dt_truoc, v_don_truoc
    from public.orders
    where created_at >= k.tu_truoc and created_at < k.den_truoc;
  end if;

  return jsonb_build_object(
    'khoang_thoi_gian', v_khoang,
    'tu_ngay',  case when k.tu = '-infinity'::timestamptz then null else k.tu end,
    'den_ngay', k.den,
    'doanh_thu', v_doanh_thu,
    'so_don', v_so_don,
    'so_don_khong_huy', v_so_don_ok,
    'gia_tri_don_trung_binh',
      case when v_so_don_ok > 0 then round(v_doanh_thu::numeric / v_so_don_ok) else 0 end,
    'so_don_huy', v_so_don_huy,
    'ty_le_huy_phan_tram',
      case when v_so_don > 0 then round(v_so_don_huy * 100.0 / v_so_don, 1) else 0 end,
    'so_don_theo_trang_thai', v_trang_thai,
    'ky_truoc', case when k.tu_truoc is null then null else jsonb_build_object(
        'doanh_thu', v_dt_truoc,
        'so_don', v_don_truoc,
        'tang_giam_doanh_thu_phan_tram', public.admin_ai_phan_tram(v_doanh_thu, v_dt_truoc),
        'tang_giam_so_don_phan_tram',    public.admin_ai_phan_tram(v_so_don,    v_don_truoc)
      ) end,
    'ghi_chu', 'Doanh thu không tính đơn đã huỷ. Số đơn tính cả đơn huỷ. '
               || 'Trạng thái: pending=đợi xác nhận, preparing=đang chuẩn bị, '
               || 'waiting_shipper=đợi shipper, shipping=đang giao, '
               || 'delivered=giao thành công, cancelled=đã huỷ.'
  );
end;
$$;


-- ════════════════════════════════════════════════════════════
--  2) BÁO CÁO SẢN PHẨM — bán chạy trong kỳ / tình trạng tồn kho
-- ════════════════════════════════════════════════════════════
create or replace function public.admin_bao_cao_san_pham(
  p_hanh_dong text default 'ban_chay',
  p_khoang    text default 'thang_nay'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  k         record;
  v_khoang  text;
  v_ds      jsonb;
  v_het     jsonb;
  v_sap_het jsonb;
  v_ton     jsonb;
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem báo cáo này.';
  end if;

  -- ── Nhánh TỒN KHO: ảnh chụp hiện tại, không phụ thuộc thời gian ──
  if p_hanh_dong = 'ton_kho' then
    select coalesce(jsonb_agg(jsonb_build_object('ten', name, 'ton_kho', stock, 'da_ban', sold_count)), '[]'::jsonb)
      into v_het
    from (select name, stock, sold_count from public.products
          where is_active and stock <= 0 order by sold_count desc limit 20) a;

    select coalesce(jsonb_agg(jsonb_build_object('ten', name, 'ton_kho', stock, 'da_ban', sold_count)), '[]'::jsonb)
      into v_sap_het
    from (select name, stock, sold_count from public.products
          where is_active and stock between 1 and 4 order by stock asc limit 20) b;

    select coalesce(jsonb_agg(jsonb_build_object('ten', name, 'ton_kho', stock, 'da_ban', sold_count)), '[]'::jsonb)
      into v_ton
    from (select name, stock, sold_count from public.products
          where is_active and stock >= 10 and sold_count = 0 order by stock desc limit 20) c;

    return jsonb_build_object(
      'hanh_dong', 'ton_kho',
      'het_hang', v_het,
      'sap_het',  v_sap_het,
      'ton_dong', v_ton,
      'ghi_chu', 'Chỉ tính sản phẩm đang hiển thị trên web. '
                 || 'sap_het = còn 1-4 sản phẩm. ton_dong = còn từ 10 trở lên mà chưa bán được cái nào. '
                 || 'Mỗi nhóm hiển thị tối đa 20 sản phẩm.'
    );
  end if;

  -- ── Nhánh BÁN CHẠY (mặc định): bung orders.items trong kỳ ──
  v_khoang := public.admin_ai_chuan_khoang(p_khoang);
  select * into k from public.admin_ai_khoang(v_khoang);

  -- LƯU Ý: items là jsonb do client ghi vào, có thể lẫn bản ghi cũ/hỏng
  -- (qty hoặc price không phải số). Lọc bằng regex và BỎ QUA dòng hỏng —
  -- không để 1 dòng lỗi làm vỡ cả báo cáo (cùng cách phòng thủ với
  -- trigger handle_new_order_stock trong sql/add-product-popularity.sql).
  with mon as (
    select
      coalesce(nullif(it->>'id',''), it->>'name')                                   as khoa,
      it->>'name'                                                                   as ten,
      case when it->>'qty'   ~ '^[0-9]+$'            then (it->>'qty')::integer   end as sl,
      case when it->>'price' ~ '^[0-9]+(\.[0-9]+)?$' then (it->>'price')::numeric end as gia
    from public.orders o,
         lateral jsonb_array_elements(coalesce(o.items, '[]'::jsonb)) it
    where o.status <> 'cancelled'
      and o.created_at >= k.tu and o.created_at < k.den
  ),
  gom as (
    select khoa,
           max(ten)                        as ten,
           sum(sl)                         as so_luong_ban,
           sum(sl * coalesce(gia, 0))::bigint as doanh_thu
    from mon
    where khoa is not null and sl is not null and sl > 0
    group by khoa
    order by doanh_thu desc, so_luong_ban desc
    limit 10
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'ten', coalesce(ten, '(không rõ tên)'),
           'so_luong_ban', so_luong_ban,
           'doanh_thu', doanh_thu)
         order by doanh_thu desc, so_luong_ban desc), '[]'::jsonb)
    into v_ds
  from gom;

  return jsonb_build_object(
    'hanh_dong', 'ban_chay',
    'khoang_thoi_gian', v_khoang,
    'tu_ngay',  case when k.tu = '-infinity'::timestamptz then null else k.tu end,
    'den_ngay', k.den,
    'san_pham', v_ds,
    'ghi_chu', 'Top 10 theo doanh thu trong kỳ. Chỉ tính đơn không huỷ. '
               || 'Bỏ qua dòng hàng lỗi dữ liệu trong đơn (nếu có).'
  );
end;
$$;


-- ════════════════════════════════════════════════════════════
--  3) BÁO CÁO KHÁCH HÀNG — tổng quan / khách chi tiêu cao
-- ════════════════════════════════════════════════════════════
create or replace function public.admin_bao_cao_khach_hang(
  p_hanh_dong text default 'tong_quan',
  p_khoang    text default 'thang_nay'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  k            record;
  v_khoang     text;
  v_moi        integer;
  v_tong       integer;
  v_nhom       jsonb;
  v_co_don     integer;
  v_quay_lai   integer;
  v_ds         jsonb;
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem báo cáo này.';
  end if;

  v_khoang := public.admin_ai_chuan_khoang(p_khoang);
  select * into k from public.admin_ai_khoang(v_khoang);

  -- ── Nhánh KHÁCH CHI TIÊU CAO ──
  -- Gộp theo SỐ ĐIỆN THOẠI (đã bỏ ký tự không phải số) — thống nhất với
  -- admin/khach-hang.html, đồng thời gom được cả đơn khách vãng lai
  -- (đặt hàng không đăng nhập nên user_id trống).
  if p_hanh_dong = 'chi_tieu_cao' then
    with don as (
      select regexp_replace(coalesce(customer_phone, ''), '\D', '', 'g') as sdt,
             customer_name, total_amount, created_at
      from public.orders
      where status <> 'cancelled'
        and created_at >= k.tu and created_at < k.den
    ),
    gom as (
      select sdt,
             (array_agg(customer_name order by created_at desc))[1] as ten,
             count(*)                                              as so_don,
             sum(total_amount)::bigint                             as tong_chi_tieu
      from don
      where sdt <> ''
      group by sdt
      order by tong_chi_tieu desc
      limit 10
    )
    -- Dùng LATERAL ... LIMIT 1 thay cho LEFT JOIN: nếu có 2 hồ sơ trùng số
    -- điện thoại thì LEFT JOIN sẽ NHÂN ĐÔI khách đó trong bảng xếp hạng.
    select coalesce(jsonb_agg(jsonb_build_object(
             'ten', coalesce(g.ten, '(không rõ tên)'),
             'so_dien_thoai', g.sdt,
             'so_don', g.so_don,
             'tong_chi_tieu', g.tong_chi_tieu,
             'nhom', coalesce(p.customer_tier, 'khong_ro')) order by g.tong_chi_tieu desc), '[]'::jsonb)
      into v_ds
    from gom g
    left join lateral (
      select pr.customer_tier
      from public.profiles pr
      where regexp_replace(coalesce(pr.phone, ''), '\D', '', 'g') = g.sdt
        and coalesce(pr.role, 'customer') <> 'admin'
      limit 1
    ) p on true;

    return jsonb_build_object(
      'hanh_dong', 'chi_tieu_cao',
      'khoang_thoi_gian', v_khoang,
      'tu_ngay',  case when k.tu = '-infinity'::timestamptz then null else k.tu end,
      'den_ngay', k.den,
      'khach_hang', v_ds,
      'ghi_chu', 'Top 10 theo tổng chi tiêu trong kỳ, gộp theo số điện thoại. '
                 || 'Không tính đơn đã huỷ. Nhóm khách: vip / regular (thường xuyên) / '
                 || 'new (mới) / churn (có nguy cơ rời).'
    );
  end if;

  -- ── Nhánh TỔNG QUAN (mặc định) ──
  select count(*) into v_moi
  from public.profiles
  where coalesce(role, 'customer') <> 'admin'
    and first_order_at is not null
    and first_order_at >= k.tu and first_order_at < k.den;

  select count(*) into v_tong
  from public.profiles
  where coalesce(role, 'customer') <> 'admin'
    and first_order_at is not null;

  select coalesce(jsonb_object_agg(nhom, so_luong), '{}'::jsonb) into v_nhom
  from (
    select coalesce(customer_tier, 'khong_ro') as nhom, count(*) as so_luong
    from public.profiles
    where coalesce(role, 'customer') <> 'admin'
    group by coalesce(customer_tier, 'khong_ro')
  ) t;

  -- Tỉ lệ quay lại tính trên TOÀN THỜI GIAN (một khách "quay lại" hay không
  -- là đặc điểm lâu dài, cắt theo tháng sẽ méo số).
  select count(*), count(*) filter (where so_don >= 2)
    into v_co_don, v_quay_lai
  from (
    select regexp_replace(coalesce(customer_phone, ''), '\D', '', 'g') as sdt,
           count(*) as so_don
    from public.orders
    where status <> 'cancelled'
      and regexp_replace(coalesce(customer_phone, ''), '\D', '', 'g') <> ''
    group by 1
  ) t;

  return jsonb_build_object(
    'hanh_dong', 'tong_quan',
    'khoang_thoi_gian', v_khoang,
    'tu_ngay',  case when k.tu = '-infinity'::timestamptz then null else k.tu end,
    'den_ngay', k.den,
    'khach_moi_trong_ky', v_moi,
    'tong_khach_tung_mua', v_tong,
    'phan_bo_nhom', v_nhom,
    'ty_le_quay_lai_phan_tram',
      case when v_co_don > 0 then round(v_quay_lai * 100.0 / v_co_don, 1) else 0 end,
    'ghi_chu', 'Không tính tài khoản quản trị. Khách mới = có đơn đầu tiên trong kỳ. '
               || 'Tỉ lệ quay lại tính trên toàn thời gian (khách có từ 2 đơn trở lên, '
               || 'gộp theo số điện thoại, không tính đơn huỷ). '
               || 'Nhóm khách: vip / regular (thường xuyên) / new (mới) / churn (có nguy cơ rời).'
  );
end;
$$;


-- ════════════════════════════════════════════════════════════
--  4) BÁO CÁO KHUYẾN MÃI — hiệu quả voucher / đợt flash sale
-- ════════════════════════════════════════════════════════════
create or replace function public.admin_bao_cao_khuyen_mai(p_hanh_dong text default 'voucher')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ds jsonb;
begin
  if not public.is_admin() then
    raise exception 'Chỉ admin mới được xem báo cáo này.';
  end if;

  -- ── Nhánh FLASH SALE ──
  if p_hanh_dong = 'flash_sale' then
    with dot as (
      select fs.id, fs.name, fs.start_at, fs.end_at, fs.is_active
      from public.flash_sales fs
      order by fs.start_at desc
      limit 20
    ),
    gom as (
      select d.id, d.name, d.start_at, d.end_at, d.is_active,
             count(i.product_id)                                     as so_san_pham,
             coalesce(sum(i.stock_limit), 0)                         as tong_suat,
             coalesce(sum(i.sold_count), 0)                          as da_ban,
             coalesce(sum(i.sold_count * i.sale_price), 0)::bigint    as doanh_thu
      from dot d
      left join public.flash_sale_items i on i.flash_sale_id = d.id
      group by d.id, d.name, d.start_at, d.end_at, d.is_active
    )
    select coalesce(jsonb_agg(jsonb_build_object(
             'ten_dot', name,
             'bat_dau', start_at,
             'ket_thuc', end_at,
             'dang_bat', is_active,
             'trang_thai', case
                when not is_active     then 'da_tat'
                when now() < start_at  then 'sap_dien_ra'
                when now() > end_at    then 'da_ket_thuc'
                else 'dang_dien_ra' end,
             'so_san_pham', so_san_pham,
             'tong_suat', tong_suat,
             'da_ban', da_ban,
             'ty_le_ban_phan_tram',
               case when tong_suat > 0 then round(da_ban * 100.0 / tong_suat, 1) else 0 end,
             'doanh_thu_uoc_tinh', doanh_thu) order by start_at desc), '[]'::jsonb)
      into v_ds
    from gom;

    return jsonb_build_object(
      'hanh_dong', 'flash_sale',
      'dot_sale', v_ds,
      'ghi_chu', 'Tối đa 20 đợt gần nhất. Doanh thu ước tính = số đã bán × giá sale của đợt.'
    );
  end if;

  -- ── Nhánh VOUCHER (mặc định) ──
  with su_dung as (
    select voucher_code,
           count(*)                              as so_don,
           coalesce(sum(discount_amount), 0)::bigint as tien_giam,
           coalesce(sum(total_amount), 0)::bigint    as doanh_thu
    from public.orders
    where status <> 'cancelled'
      and voucher_code is not null and voucher_code <> ''
    group by voucher_code
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'ma', v.code,
           'loai_giam', v.discount_type,
           'gia_tri_giam', v.discount_value,
           'don_toi_thieu', v.min_order,
           'dang_bat', v.is_active,
           'ngay_het_han', v.end_date,
           'tong_luot_cho_phep', v.total_quantity,
           'so_don_da_dung', coalesce(s.so_don, 0),
           'luot_con_lai', greatest(coalesce(v.total_quantity, 0) - coalesce(s.so_don, 0), 0),
           'tong_tien_giam', coalesce(s.tien_giam, 0),
           'doanh_thu_tu_don', coalesce(s.doanh_thu, 0))
         order by coalesce(s.so_don, 0) desc, v.created_at desc), '[]'::jsonb)
    into v_ds
  from public.vouchers v
  left join su_dung s on s.voucher_code = v.code;

  return jsonb_build_object(
    'hanh_dong', 'voucher',
    'voucher', v_ds,
    'ghi_chu', 'Thống kê trên toàn bộ lịch sử, không tính đơn đã huỷ. '
               || 'loai_giam: percent = giảm theo %, amount = giảm số tiền cố định.'
  );
end;
$$;


-- ────────────────────────────────────────────────────────────
--  QUYỀN GỌI HÀM
--  Người CHƯA đăng nhập (anon) không cần gọi báo cáo quản trị →
--  thu hồi hẳn. Người đã đăng nhập gọi được nhưng sẽ bị chặn ngay
--  bởi is_admin() bên trong nếu không phải admin.
-- ────────────────────────────────────────────────────────────
revoke execute on function public.admin_bao_cao_kinh_doanh(text)        from public, anon;
revoke execute on function public.admin_bao_cao_san_pham(text, text)    from public, anon;
revoke execute on function public.admin_bao_cao_khach_hang(text, text)  from public, anon;
revoke execute on function public.admin_bao_cao_khuyen_mai(text)        from public, anon;

grant execute on function public.admin_bao_cao_kinh_doanh(text)       to authenticated;
grant execute on function public.admin_bao_cao_san_pham(text, text)   to authenticated;
grant execute on function public.admin_bao_cao_khach_hang(text, text) to authenticated;
grant execute on function public.admin_bao_cao_khuyen_mai(text)       to authenticated;


-- ============================================================
--  KIỂM CHỨNG SAU KHI CHẠY (làm theo đúng thứ tự):
--   (a) Gọi bằng anon key → phải bị TỪ CHỐI QUYỀN:
--       curl -X POST 'https://<proj>.supabase.co/rest/v1/rpc/admin_bao_cao_kinh_doanh' \
--            -H 'apikey: <anon key>' -H 'Content-Type: application/json' \
--            -d '{"p_khoang":"thang_nay"}'
--   (b) Đăng nhập tài khoản KHÁCH thường rồi gọi → lỗi
--       "Chỉ admin mới được xem báo cáo này."
--   (c) Đăng nhập ADMIN rồi gọi → trả về JSON báo cáo đầy đủ.
--   (d) Đối chiếu số: admin_bao_cao_kinh_doanh('hom_nay').doanh_thu
--       phải KHỚP thẻ "Doanh thu" trên admin/dashboard.html.
--  Nếu (a) hoặc (b) KHÔNG bị chặn → dừng ngay, báo lại: nghĩa là
--  guard is_admin() không chạy, dữ liệu kinh doanh đang bị lộ.
-- ============================================================
