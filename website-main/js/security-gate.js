/* ============================================================
   SECURITY GATE — cổng kiểm tra rate-limit trước các hành động
   nhạy cảm (đăng nhập, liên hệ, đánh giá, đặt hàng, áp mã).
   ------------------------------------------------------------
   Toàn bộ ngưỡng/thuật toán thật nằm trong Supabase (schema
   `security`, không public qua API) — file này CHỈ gọi hàm và
   phản ứng UI, không chứa số liệu hay logic bảo mật thật.
   Cần chạy sql/security-rate-limit.sql trước khi dùng file này.
   Xem CLAUDE.md mục "Kiến trúc bảo mật" trước khi sửa file này.
   ============================================================ */
(function () {
  'use strict';

  // Định danh thiết bị cho hành động KHÔNG cần đăng nhập (vd form
  // Liên hệ, Đánh giá). Không đáng tin tuyệt đối (xoá localStorage là
  // đổi được định danh) — chỉ là lớp chống lạm dụng cấp cơ bản.
  function deviceId() {
    var KEY = 'yd-dv';
    try {
      var v = localStorage.getItem(KEY);
      if (!v) {
        v = (window.crypto && crypto.randomUUID)
          ? crypto.randomUUID()
          : ('dv-' + Date.now() + '-' + Math.random().toString(36).slice(2));
        localStorage.setItem(KEY, v);
      }
      return v;
    } catch (e) {
      return 'anon';
    }
  }

  // Trả về Promise<boolean>: true = được phép tiếp tục, false = đã
  // vượt ngưỡng. Lỗi mạng/hàm chưa deploy → mặc định CHO PHÉP
  // (fail-open) — lớp này chỉ chống lạm dụng, không phải biên bảo
  // mật chính, không được để lỗi ở đây khoá luôn tính năng thật.
  function check(bucket, identifier) {
    if (typeof getSupabase !== 'function') return Promise.resolve(true);
    try {
      return getSupabase()
        .rpc('check_rate_limit', { p_bucket: bucket, p_identifier: identifier })
        .then(function (res) {
          if (res.error) return true;
          return res.data !== false;
        })
        .catch(function () { return true; });
    } catch (e) {
      return Promise.resolve(true);
    }
  }

  // ─── ADMIN GUARD (chỉ dùng ở các trang admin) ────────────────
  // Xác thực lại phiên Supabase THẬT + profiles.role tại chỗ mỗi lần
  // tải trang — không bao giờ tin localStorage để quyết định quyền vào.
  // Khác với check() ở trên, hàm này FAIL-CLOSED: bất kỳ bước nào lỗi
  // hoặc không phải admin thật → đá về trang đăng nhập ngay, vì đây là
  // biên kiểm soát truy cập thật, không phải lớp chống lạm dụng.
  // Dùng: SecurityGate.requireAdmin().then(function(user){ ...tải dữ liệu trang... });
  function requireAdmin(loginPath) {
    var path = loginPath || 'index.html';
    function deny(shouldSignOut) {
      try { localStorage.removeItem('yen-duyen-admin'); } catch (e) {}
      if (shouldSignOut && typeof getSupabase === 'function') {
        try { getSupabase().auth.signOut(); } catch (e) {}
      }
      window.location.replace(path);
      return new Promise(function () {}); // đang chuyển trang, không resolve nữa
    }
    if (typeof getSupabase !== 'function' || typeof getCurrentUser !== 'function') return deny(false);
    return getCurrentUser().then(function (u) {
      if (!u) return deny(false);
      return getSupabase().from('profiles').select('role').eq('id', u.id).single()
        .then(function (r) {
          if (!r.data || r.data.role !== 'admin') return deny(true);
          return u;
        });
    }).catch(function () { return deny(false); });
  }

  window.SecurityGate = { check: check, deviceId: deviceId, requireAdmin: requireAdmin };
})();
