// ============================================================
// TOOL CHẠY Ở CLIENT — Nhóm A: chỉ đọc dữ liệu CÔNG KHAI, KHÔNG cần đăng
// nhập/xác thực danh tính (đúng nguyên tắc đã chốt: tránh mọi tool đụng dữ
// liệu cá nhân/nhạy cảm ở giai đoạn này). Dùng Supabase THẬT của site chính
// (chỉ đọc — select), không phải dữ liệu giả lập nữa.
//
// LƯU Ý BẢO MẬT: bảng "vouchers" CỐ TÌNH không có tool ở đây — anon không
// có quyền đọc trực tiếp (đã bị khoá sau 1 lỗ hổng thật, xem
// sql/fix-vouchers-read-lockdown.sql ở repo chính), RPC check_voucher cũng
// chỉ cấp quyền cho authenticated. Không tự ý mở lại.
// ============================================================

// ── san_pham (bảng products) ──
// hanh_dong = 'tim_kiem': tìm theo từ khoá + lọc giá tối đa (tuỳ chọn).
// hanh_dong = 'chi_tiet': lấy đầy đủ 1 sản phẩm theo id.
async function san_pham(args) {
  var hanhDong = args && args.hanh_dong;
  var sb = getSupabase();

  if (hanhDong === 'chi_tiet') {
    var id = args && args.id;
    if (!id) return { loi: 'Thiếu id sản phẩm.' };
    var res1 = await sb.from('products')
      .select('id,name,price,old_price,category,description,stock,image_url,badge')
      .eq('id', id).eq('is_active', true).maybeSingle();
    if (res1.error) return { loi: res1.error.message };
    if (!res1.data) return { loi: 'Không tìm thấy sản phẩm với id này (có thể đã ngừng bán).' };
    return { san_pham: res1.data };
  }

  // Mặc định: tim_kiem
  var tuKhoa = (args && args.tu_khoa || '').trim();
  var giaToiDa = args && args.gia_toi_da;
  var q = sb.from('products')
    .select('id,name,price,old_price,category,stock,image_url')
    .eq('is_active', true);
  if (tuKhoa) {
    var kw = '%' + tuKhoa.replace(/[%,()]/g, '') + '%';
    q = q.or('name.ilike.' + kw + ',category.ilike.' + kw + ',description.ilike.' + kw);
  }
  if (giaToiDa) q = q.lte('price', Number(giaToiDa));
  q = q.order('sold_count', { ascending: false }).limit(8);

  var res2 = await q;
  if (res2.error) return { loi: res2.error.message };
  return { so_luong_tim_thay: (res2.data || []).length, san_pham: res2.data || [] };
}

// ── flash_sale (bảng flash_sales + flash_sale_items) — 1 hành động duy nhất:
// đợt đang diễn ra, hoặc nếu không có thì đợt sắp diễn ra gần nhất. Cùng
// logic với loadFlashSale() ở index.html trang chính (không bịa cơ chế mới).
async function flash_sale() {
  var sb = getSupabase();
  var res = await sb.from('flash_sales').select('*').eq('is_active', true).order('start_at', { ascending: true });
  if (res.error) return { loi: res.error.message };
  var rows = res.data || [];
  if (!rows.length) return { trang_thai: 'khong_co' };

  var now = Date.now();
  var active = rows.filter(function (fs) { return new Date(fs.start_at).getTime() <= now && new Date(fs.end_at).getTime() >= now; });
  var chosen, trangThai;
  if (active.length) {
    chosen = active[0]; trangThai = 'dang_dien_ra';
  } else {
    var upcoming = rows.filter(function (fs) { return new Date(fs.start_at).getTime() > now; })
      .sort(function (a, b) { return new Date(a.start_at) - new Date(b.start_at); });
    if (!upcoming.length) return { trang_thai: 'khong_co' };
    chosen = upcoming[0]; trangThai = 'sap_dien_ra';
  }

  var itemsRes = await sb.from('flash_sale_items').select('*').eq('flash_sale_id', chosen.id);
  if (itemsRes.error) return { loi: itemsRes.error.message };
  var items = itemsRes.data || [];
  if (!items.length) return { trang_thai: 'khong_co' };

  var ids = items.map(function (it) { return it.product_id; });
  var prodRes = await sb.from('products').select('id,name,price,image_url').in('id', ids).eq('is_active', true);
  if (prodRes.error) return { loi: prodRes.error.message };
  var productMap = {};
  (prodRes.data || []).forEach(function (p) { productMap[p.id] = p; });

  var sanPham = items.map(function (it) {
    var p = productMap[it.product_id];
    if (!p) return null;
    var giamPhanTram = p.price > it.sale_price ? Math.round((1 - it.sale_price / p.price) * 100) : 0;
    return { ten: p.name, gia_goc: p.price, gia_sale: it.sale_price, giam_phan_tram: giamPhanTram, con_lai: Math.max(0, it.stock_limit - it.sold_count) };
  }).filter(Boolean);

  return {
    trang_thai: trangThai,
    ten_dot: chosen.name,
    bat_dau: chosen.start_at,
    ket_thuc: chosen.end_at,
    san_pham: sanPham,
  };
}

// ── thong_tin_cua_hang (bảng site_settings) — 1 hành động duy nhất ──
async function thong_tin_cua_hang() {
  var sb = getSupabase();
  var res = await sb.from('site_settings').select('shop_name,phone,zalo_phone,facebook_url,email,address').limit(1).maybeSingle();
  if (res.error) return { loi: res.error.message };
  if (!res.data) return { loi: 'Chưa có thông tin cửa hàng.' };
  return res.data;
}

// ── Dispatcher — gọi theo tên tool, ĐÃ khớp đúng CLIENT_TOOL_DECLARATIONS
// trong server.js. Trả về Promise (khác bản demo cũ — giờ là gọi mạng thật).
async function chayToolClient(name, args) {
  if (name === 'san_pham') return san_pham(args || {});
  if (name === 'flash_sale') return flash_sale();
  if (name === 'thong_tin_cua_hang') return thong_tin_cua_hang();
  throw new Error('Không rõ tool client "' + name + '"');
}

export { chayToolClient };
