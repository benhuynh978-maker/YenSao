// ============================================================
//  AUTH WIDGET — Nút Đăng nhập / Avatar + dropdown cho header
//  Yến Sào Yến Duyên. Script thường (không module).
//  Cách dùng trên mỗi trang:
//    1) Trong header (vùng .header-actions) đặt:  <div id="auth-slot"></div>
//    2) Nạp 3 script trước </body>:
//         <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//         <script src="js/supabase-client.js"></script>
//         <script src="js/auth-widget.js"></script>
//  Yêu cầu: supabase-client.js phải nạp TRƯỚC file này.
// ============================================================
(function () {
  // ─── CSS tự chèn 1 lần ─────────────────────────────────────
  function injectStyles() {
    if (document.getElementById('auth-widget-style')) return;
    var css =
      '.aw-wrap{position:relative;display:inline-flex;align-items:center;}' +
      '.aw-login-btn{display:inline-flex;align-items:center;gap:6px;padding:7px 13px;border-radius:8px;' +
        'background:var(--color-gold,#D4AF37);color:#3E2723;font-weight:700;font-size:.82rem;text-decoration:none;' +
        'font-family:var(--font-body,sans-serif);transition:opacity .2s,transform .2s;white-space:nowrap;}' +
      '.aw-login-btn:hover{opacity:.9;transform:translateY(-1px);}' +
      '.aw-avatar{width:40px;height:40px;border-radius:50%;border:2px solid var(--color-gold,#D4AF37);cursor:pointer;' +
        'display:flex;align-items:center;justify-content:center;color:#fff;font-weight:700;font-size:1rem;overflow:hidden;' +
        'font-family:var(--font-body,sans-serif);padding:0;background:none;flex-shrink:0;}' +
      '.aw-avatar img{width:100%;height:100%;object-fit:cover;}' +
      '.aw-menu{position:absolute;top:calc(100% + 10px);right:0;min-width:220px;background:#fff;border-radius:12px;' +
        'box-shadow:0 8px 30px rgba(62,39,35,.18);border:1px solid rgba(212,175,55,.2);padding:8px;z-index:1200;' +
        'opacity:0;visibility:hidden;transform:translateY(-6px);transition:opacity .18s,transform .18s,visibility .18s;}' +
      '.aw-menu.is-open{opacity:1;visibility:visible;transform:translateY(0);}' +
      '.aw-menu-head{padding:10px 12px 12px;border-bottom:1px solid #f0ebe4;margin-bottom:6px;}' +
      '.aw-menu-name{font-weight:700;color:#3E2723;font-size:.95rem;line-height:1.2;}' +
      '.aw-menu-sub{font-size:.78rem;color:#9ca3af;margin-top:3px;word-break:break-all;}' +
      '.aw-menu-item{display:flex;align-items:center;gap:11px;padding:10px 12px;border-radius:8px;color:#3E2723;' +
        'text-decoration:none;font-size:.9rem;font-weight:500;width:100%;border:none;background:none;cursor:pointer;' +
        'font-family:var(--font-body,sans-serif);text-align:left;transition:background .15s;box-sizing:border-box;}' +
      '.aw-menu-item:hover{background:var(--color-cream,#FAF6F1);}' +
      '.aw-menu-item svg{color:#8D6E63;flex-shrink:0;}' +
      '.aw-menu-item--danger{color:#b91c1c;}.aw-menu-item--danger svg{color:#b91c1c;}' +
      '.aw-divider{height:1px;background:#f0ebe4;margin:6px 4px;}' +
      '@media(max-width:1150px){.aw-login-btn span{display:none;}.aw-login-btn{padding:8px;}}';
    var st = document.createElement('style');
    st.id = 'auth-widget-style';
    st.textContent = css;
    document.head.appendChild(st);
  }

  function icon(path) {
    return '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + path + '</svg>';
  }
  var ICON_USER  = icon('<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>');
  var ICON_BOX   = icon('<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/>');
  var ICON_OUT   = icon('<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>');
  var ICON_LOGIN = icon('<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/><line x1="15" y1="12" x2="3" y2="12"/>');

  function renderLoggedOut(slot) {
    slot.innerHTML =
      '<a class="aw-login-btn" href="dang-nhap.html?redirect=' +
        encodeURIComponent(window.location.pathname.split('/').pop() + window.location.search) + '">' +
        ICON_LOGIN + '<span>Đăng nhập</span></a>';
  }

  function renderLoggedIn(slot, user, profile) {
    var name = (profile && profile.full_name) || (user.user_metadata && user.user_metadata.full_name) || 'Tài khoản';
    var avatarUrl = profile && profile.avatar_url;
    // dòng phụ: hiển thị SĐT nếu là tài khoản phone, ngược lại email thật
    var sub;
    if (isPhoneEmail(user.email)) sub = (profile && profile.phone) || normalizePhone(user.email.split('@')[0]);
    else sub = user.email;

    var avatarInner;
    if (avatarUrl) {
      avatarInner = '<img src="' + avatarUrl + '" alt="Ảnh đại diện">';
    } else {
      avatarInner = avatarInitial(name);
    }
    var gradient = avatarGradientFor(user.id);

    slot.innerHTML =
      '<div class="aw-wrap">' +
        '<button class="aw-avatar" id="aw-avatar-btn" aria-label="Tài khoản của tôi" aria-haspopup="true" aria-expanded="false"' +
          (avatarUrl ? '' : ' style="background:' + gradient + ';"') + '>' + avatarInner + '</button>' +
        '<div class="aw-menu" id="aw-menu" role="menu">' +
          '<div class="aw-menu-head">' +
            '<div class="aw-menu-name">' + escapeHtml(name) + '</div>' +
            '<div class="aw-menu-sub">' + escapeHtml(sub || '') + '</div>' +
          '</div>' +
          '<a class="aw-menu-item" role="menuitem" href="ho-so.html">' + ICON_USER + 'Hồ sơ</a>' +
          '<a class="aw-menu-item" role="menuitem" href="don-hang-cua-toi.html">' + ICON_BOX + 'Đơn hàng của tôi</a>' +
          '<div class="aw-divider"></div>' +
          '<button class="aw-menu-item aw-menu-item--danger" role="menuitem" id="aw-logout-btn">' + ICON_OUT + 'Đăng xuất</button>' +
        '</div>' +
      '</div>';

    var btn = slot.querySelector('#aw-avatar-btn');
    var menu = slot.querySelector('#aw-menu');
    function closeMenu() { menu.classList.remove('is-open'); btn.setAttribute('aria-expanded', 'false'); }
    function toggleMenu(e) {
      e.stopPropagation();
      var open = menu.classList.toggle('is-open');
      btn.setAttribute('aria-expanded', String(open));
    }
    btn.addEventListener('click', toggleMenu);
    document.addEventListener('click', function (e) {
      if (!slot.contains(e.target)) closeMenu();
    });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeMenu(); });
    slot.querySelector('#aw-logout-btn').addEventListener('click', function () {
      signOutAndRedirect('index.html');
    });
  }

  function escapeHtml(s) {
    return ('' + s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function render(slot) {
    getCurrentUser().then(function (user) {
      if (!user) { renderLoggedOut(slot); return; }
      // có user → lấy profile để hiện tên + avatar (không chặn nếu lỗi)
      getSupabase().from('profiles').select('*').eq('id', user.id).single().then(function (res) {
        renderLoggedIn(slot, user, res.data || null);
      });
    });
  }

  function init() {
    var slot = document.getElementById('auth-slot');
    if (!slot) return;
    injectStyles();
    render(slot);
    // cập nhật lại khi trạng thái đăng nhập thay đổi (đăng nhập/đăng xuất ở tab khác)
    getSupabase().auth.onAuthStateChange(function () { render(slot); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
