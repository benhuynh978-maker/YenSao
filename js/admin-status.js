/* ============================================================
   ADMIN STATUS — Huy hiệu DEMO / LIVE cho trang quản trị
   Yến Sào Yến Duyên
   ------------------------------------------------------------
   - Tự gắn 1 huy hiệu nhỏ cạnh tên trang ở thanh trên cùng.
       DEMO = trang dùng dữ liệu mẫu, CHƯA nối Supabase.
       LIVE = trang đã nối Supabase, dùng dữ liệu thật.
   - Trang DEMO còn được thêm 1 dải băng nhắc ở đầu nội dung.
   - MUỐN ĐỔI TRẠNG THÁI 1 TRANG: chỉ cần sửa giá trị trong
     PAGE_STATUS bên dưới ('demo' hoặc 'live').
   - Viết theo kiểu IIFE + class có tiền tố "yd-status-" để
     KHÔNG đè / không bị đè bởi CSS/JS khác trên trang.
   ============================================================ */
(function () {
  'use strict';

  // ── BẢNG KÊ TRẠNG THÁI TỪNG TRANG (theo tên file) ──────────
  var PAGE_STATUS = {
    'dashboard.html'  : 'demo',
    'don-hang.html'   : 'live',   // đã đọc đơn thật từ Supabase
    'san-pham.html'   : 'live',
    'voucher.html'    : 'live',   // CRUD voucher đã nối Supabase thật, chỉ 2 lựa chọn scope "Khách mới/VIP" còn demo (đã tự ghi chú trong dropdown)
    'blog.html'       : 'live',   // đã chạy add-blog-fields.sql + add-blog-featured.sql, CRUD + hiển thị thật
    'khach-hang.html' : 'live',   // tổng hợp thật từ orders (gộp theo SĐT) + lịch sử đơn thật; lọc Nhóm/Sắp xếp + Export Excel đều dùng dữ liệu thật
    'phan-hoi.html'   : 'live',   // đã nối reviews + contact_messages thật
    'cai-dat.html'    : 'demo',
    'sao-luu.html'    : 'live'    // trang sao lưu chạy thật
  };

  function init() {
    if (window.__ydStatusDone) return;   // chống chạy 2 lần
    window.__ydStatusDone = true;

    var file = (location.pathname.split('/').pop() || '').toLowerCase();
    var status = PAGE_STATUS[file];
    if (!status) return;                  // trang không khai báo → bỏ qua

    injectStyle();
    var isDemo = status === 'demo';

    // 1) Huy hiệu cạnh tên trang
    var badge = document.createElement('span');
    badge.className = 'yd-status-badge ' + (isDemo ? 'yd-status-badge--demo' : 'yd-status-badge--live');
    badge.textContent = isDemo ? 'DEMO' : 'LIVE';
    badge.title = isDemo
      ? 'Trang DEMO — dữ liệu là mẫu, chưa kết nối Supabase'
      : 'Trang LIVE — đã kết nối Supabase, dùng dữ liệu thật';

    var title = document.querySelector('.admin-topbar__title');
    if (title && title.parentNode) {
      title.parentNode.insertBefore(badge, title.nextSibling);
    } else {
      badge.classList.add('yd-status-badge--floating');  // dự phòng: gắn nổi ở góc
      document.body.appendChild(badge);
    }

    // 2) Dải băng nhắc — chỉ cho trang DEMO
    if (isDemo) {
      var main = document.querySelector('.admin-main');
      if (main) {
        var bar = document.createElement('div');
        bar.className = 'yd-status-banner';
        bar.innerHTML = '⚠️ <strong>Trang DEMO</strong> — dữ liệu hiển thị là mẫu, chưa kết nối Supabase. Các nút bấm ở đây chỉ để minh hoạ.';
        main.insertBefore(bar, main.firstChild);
      }
    }
  }

  function injectStyle() {
    if (document.getElementById('yd-status-style')) return;
    var css =
      '.yd-status-badge{display:inline-block;margin-left:10px;padding:2px 10px;border-radius:20px;' +
      'font-size:.7rem;font-weight:800;letter-spacing:.5px;vertical-align:middle;line-height:1.7;}' +
      '.yd-status-badge--demo{background:#fef3c7;color:#92400e;border:1px solid #fde68a;}' +
      '.yd-status-badge--live{background:#dcfce7;color:#166534;border:1px solid #86efac;}' +
      '.yd-status-badge--floating{position:fixed;top:12px;right:12px;z-index:9999;margin:0;}' +
      '.yd-status-banner{background:#fffbeb;border:1px solid #fde68a;color:#92400e;' +
      'border-radius:10px;padding:10px 16px;margin-bottom:18px;font-size:.86rem;line-height:1.5;}';
    var style = document.createElement('style');
    style.id = 'yd-status-style';
    style.textContent = css;
    document.head.appendChild(style);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
