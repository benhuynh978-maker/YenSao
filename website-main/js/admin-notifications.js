/* ============================================================
   HỆ THỐNG THÔNG BÁO ADMIN — chuông + toast top-center dùng chung
   cho MỌI trang admin (trừ trang đăng nhập). Đây là hệ thống thông
   báo RIÊNG BIỆT với toast lỗi/lưu ý thông thường của từng trang —
   file này không đụng và không phụ thuộc gì vào showToast() cục bộ
   (nếu có) của các trang khác.

   Cần: js/supabase-client.js đã load trước (getSupabase()), và
   sql/add-admin-notifications.sql đã chạy (bảng + RLS is_admin()
   + Realtime publication). Bảo mật: mọi dữ liệu đọc về đều đi qua
   RLS is_admin() — không cần tự kiểm quyền lại ở đây, không admin
   thật thì query rỗng/lỗi, chuông chỉ đơn giản không hiện gì.

   Cách dùng: thêm 1 dòng
     <script src="../js/admin-notifications.js"></script>
   vào các trang admin (sau supabase-client.js), không cần thêm HTML
   gì khác — chuông + khung toast tự mount vào .admin-topbar__right.
   ============================================================ */
(function () {
  'use strict';

  var GROUP_THRESHOLD = 3; // từ 3 thông báo đang mở cùng lúc trở lên → gộp
  var openToasts = [];     // {id, el} các thẻ thông báo riêng đang mở
  var summaryEl = null;    // thẻ gộp đang mở (nếu có)
  var root = null;

  function esc(s) {
    return (s == null ? '' : String(s)).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  var ICONS = {
    order: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8h12l-1 12H7L6 8Z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/></svg>',
    customer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><circle cx="9" cy="9" r="3"/><path d="M4 19c0-3 2.3-5 5-5s5 2 5 5"/><circle cx="17" cy="10" r="2.4"/><path d="M15.5 14.2c2 .3 3.5 1.9 3.5 4"/></svg>',
    feedback: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.4 8.4 0 0 1-8.9 8.4 9 9 0 0 1-3.6-.7L3 20l1-4.5A8.4 8.4 0 1 1 21 11.5Z"/></svg>',
    voucher: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20.6 12.9 12.9 20.6a2 2 0 0 1-2.8 0l-7-7a2 2 0 0 1 0-2.8L10.8 3a2 2 0 0 1 1.4-.6h5.4A2.4 2.4 0 0 1 20 4.8v5.4a2 2 0 0 1-.6 1.4Z"/><circle cx="15.5" cy="7.5" r="1.5"/></svg>',
    flashsale: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M13 3 4 14h6l-1 7 9-11h-6l1-7Z"/></svg>',
    product: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M21 8 12 3 3 8v8l9 5 9-5V8Z"/><path d="M3 8l9 5 9-5M12 13v8"/></svg>',
    bell: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/></svg>'
  };

  function goToHistory() {
    window.location.href = 'thong-bao.html';
  }

  function closeToastEl(el) {
    if (el.dataset.closing) return;
    el.dataset.closing = '1';
    el.classList.remove('is-show');
    el.classList.add('is-hide');
    var done = false;
    function finish() { if (done) return; done = true; el.remove(); }
    el.addEventListener('animationend', finish, { once: true });
    setTimeout(finish, 350);
  }

  function closeIndividualToast(id) {
    var idx = openToasts.findIndex(function (t) { return t.id === id; });
    if (idx === -1) return;
    closeToastEl(openToasts[idx].el);
    openToasts.splice(idx, 1);
  }

  function closeSummaryToast() {
    if (!summaryEl) return;
    closeToastEl(summaryEl);
    summaryEl = null;
  }

  function buildCardShell(iconKey, innerHtml, onCloseClick) {
    var card = document.createElement('div');
    card.className = 'admin-notif-toast';
    card.setAttribute('role', 'status');
    card.innerHTML =
      '<div class="admin-notif-toast__icon">' + (ICONS[iconKey] || ICONS.bell) + '</div>' +
      innerHtml +
      '<button type="button" class="admin-notif-toast__close" aria-label="Đóng thông báo">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 5l14 14M19 5 5 19"/></svg></button>';
    card.addEventListener('click', function (e) {
      if (e.target.closest('.admin-notif-toast__close')) return;
      goToHistory();
    });
    card.querySelector('.admin-notif-toast__close').addEventListener('click', function (e) {
      e.stopPropagation();
      onCloseClick();
    });
    root.appendChild(card);
    requestAnimationFrame(function () {
      requestAnimationFrame(function () { card.classList.add('is-show'); });
    });
    return card;
  }

  function showIndividualToast(row) {
    var id = row.id;
    var card = buildCardShell(row.system,
      '<div class="admin-notif-toast__body">' +
      '<span class="admin-notif-toast__label"><span class="bead"></span>' + esc(row.title) + '</span>' +
      '<span class="admin-notif-toast__content">' + esc(row.content) + '</span>' +
      '</div>',
      function () { closeIndividualToast(id); });
    openToasts.push({ id: id, el: card });
  }

  function showOrUpdateSummaryToast(count) {
    if (summaryEl) {
      var content = summaryEl.querySelector('.admin-notif-toast__content');
      if (content) content.textContent = 'Bạn đang có ' + count + ' thông báo đang chờ';
      return;
    }
    summaryEl = buildCardShell('bell',
      '<div class="admin-notif-toast__body">' +
      '<span class="admin-notif-toast__label"><span class="bead"></span>Thông báo</span>' +
      '<span class="admin-notif-toast__content">Bạn đang có ' + count + ' thông báo đang chờ</span>' +
      '</div>',
      function () { closeSummaryToast(); });
    summaryEl.classList.add('admin-notif-toast--summary');
  }

  function handleNewNotification(row) {
    refreshUnreadCount().then(function (unread) {
      if (summaryEl) {
        showOrUpdateSummaryToast(unread);
        return;
      }
      if (openToasts.length + 1 >= GROUP_THRESHOLD) {
        openToasts.forEach(function (t) { closeToastEl(t.el); });
        openToasts = [];
        showOrUpdateSummaryToast(unread);
      } else {
        showIndividualToast(row);
      }
    });
  }

  function setBadge(count) {
    var badge = document.getElementById('admin-notif-badge');
    if (!badge) return;
    if (!count || count <= 0) {
      badge.hidden = true;
      badge.textContent = '';
    } else {
      badge.hidden = false;
      badge.textContent = count > 99 ? '99+' : String(count);
    }
  }

  function refreshUnreadCount() {
    if (typeof getSupabase !== 'function') return Promise.resolve(0);
    return getSupabase()
      .from('admin_notifications')
      .select('id', { count: 'exact', head: true })
      .eq('is_read', false)
      .then(function (res) {
        var count = res.count || 0;
        setBadge(count);
        return count;
      })
      .catch(function () { return 0; });
  }

  function mountBell() {
    var right = document.querySelector('.admin-topbar__right');
    if (!right) return;
    right.insertAdjacentHTML('afterbegin',
      '<button type="button" class="admin-notif-bell" id="admin-notif-bell" aria-label="Xem thông báo" title="Thông báo">' +
      ICONS.bell +
      '<span class="admin-notif-badge" id="admin-notif-badge" hidden></span>' +
      '</button>');
    var bell = document.getElementById('admin-notif-bell');
    if (bell) bell.addEventListener('click', goToHistory);
  }

  function subscribeRealtime() {
    if (typeof getSupabase !== 'function') return;
    getSupabase()
      .channel('admin-notifications-global')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'admin_notifications' }, function (payload) {
        handleNewNotification(payload.new);
      })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'admin_notifications' }, function () {
        refreshUnreadCount();
      })
      .subscribe();
  }

  function init() {
    root = document.createElement('div');
    root.id = 'admin-notif-root';
    document.body.appendChild(root);

    mountBell();
    refreshUnreadCount();
    subscribeRealtime();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
