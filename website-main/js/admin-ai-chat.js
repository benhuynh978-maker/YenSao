// ============================================================
// AI CHAT ADMIN — "Trợ lý phân tích kinh doanh". Script thường (KHÔNG module).
// Tự chèn nút chat vào .float-cta, chạy vòng lặp function-calling qua relay
// /api/admin-chat. 4 tool đều là RPC báo cáo, gọi dưới PHIÊN ADMIN THẬT
// (getSupabase()) — RLS + is_admin() trong RPC tự chặn (đã pentest).
//
// GUARD: chỉ dựng widget khi xác thực lại phiên Supabase thật + profiles.role
// = 'admin' (KHÔNG tin localStorage). Không phải admin → không chèn gì.
//
// Cần supabase-client.js (getSupabase) nạp TRƯỚC. Lưu hội thoại vào
// sessionStorage để chuyển trang admin không mất mạch trò chuyện.
//
// RELAY: đường dẫn tương đối /api/admin-chat (trang do relay serve cùng
// origin khi test local). Đổi thành URL tuyệt đối khi deploy khác origin.
// ============================================================
(function () {
  var RELAY_URL = '/api/admin-chat';
  var CLIENT_TOOL_ROUND_LIMIT = 3;
  var TONG_TIMEOUT_MS = 40000;
  var STORAGE_KEY = 'yd-admin-ai-chat';

  var GEAR = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>';
  var GEAR_SM = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>';
  var GEAR_XS = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><circle cx="12" cy="12" r="3.2"/></svg>';
  var CLOSE = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var CLOSE_SM = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var SEND = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>';

  var TOGGLE_HTML =
    '<button class="ai-chat-toggle" id="ai-chat-toggle" aria-label="Mở trợ lý kinh doanh" aria-expanded="false" aria-controls="ai-chat-panel">'
    + '<span class="ai-chat-toggle__icon">' + GEAR + '</span>'
    + '<span class="ai-chat-toggle__close">' + CLOSE + '</span>'
    + '<span>Trợ lý</span>'
    + '</button>';

  var PANEL_HTML =
    '<div class="ai-chat-panel" id="ai-chat-panel" role="dialog" aria-modal="false" aria-label="Trợ lý phân tích kinh doanh">'
    + '<div class="ai-chat-panel__header">'
    + '<span class="ai-chat-panel__avatar">' + GEAR_SM + '</span>'
    + '<span class="ai-chat-panel__title">'
    + '<span class="ai-chat-panel__name">Trợ lý kinh doanh</span>'
    + '<span class="ai-chat-panel__status">Chỉ đọc — báo cáo số liệu thật</span>'
    + '</span>'
    + '<button class="ai-chat-panel__close" id="ai-chat-close" aria-label="Đóng">' + CLOSE_SM + '</button>'
    + '</div>'
    + '<div class="ai-chat-panel__messages" id="ai-chat-messages"></div>'
    + '<div class="ai-chat-panel__suggestions" id="ai-chat-suggestions">'
    + '<button type="button" class="ai-chat-chip" data-prompt="Doanh thu hôm nay bao nhiêu, so với hôm qua thế nào?">Doanh thu hôm nay</button>'
    + '<button type="button" class="ai-chat-chip" data-prompt="Sản phẩm nào bán chạy nhất tháng này?">Bán chạy tháng này</button>'
    + '<button type="button" class="ai-chat-chip" data-prompt="Có sản phẩm nào sắp hết hàng không?">Sắp hết hàng</button>'
    + '<button type="button" class="ai-chat-chip" data-prompt="Tháng này có bao nhiêu khách hàng mới?">Khách hàng mới</button>'
    + '<button type="button" class="ai-chat-suggestions__hide" data-hide-suggestions aria-label="Ẩn gợi ý">Ẩn ✕</button>'
    + '</div>'
    + '<div class="ai-chat-panel__input-row">'
    + '<input type="text" class="ai-chat-panel__input" id="ai-chat-input" placeholder="Hỏi về doanh thu, đơn hàng, khách, khuyến mãi..." aria-label="Nhập câu hỏi">'
    + '<button type="button" class="ai-chat-panel__send" id="ai-chat-send" aria-label="Gửi">' + SEND + '</button>'
    + '</div>'
    + '</div>';

  // ══════════════════════════════════════════════════════════
  // 4 TOOL = RPC BÁO CÁO (sql/add-admin-ai-reports.sql). Chạy dưới phiên admin.
  // Khớp ADMIN_TOOL_DECLARATIONS trong ai-chat/server.js.
  // ══════════════════════════════════════════════════════════
  function rpc(name, params) {
    return getSupabase().rpc(name, params).then(function (res) {
      if (res.error) return { loi: res.error.message };
      return res.data;
    });
  }
  function chayToolAdmin(name, args) {
    args = args || {};
    var khoang = args.khoang_thoi_gian || 'thang_nay';
    if (name === 'bao_cao_kinh_doanh') return rpc('admin_bao_cao_kinh_doanh', { p_khoang: khoang });
    if (name === 'bao_cao_san_pham') return rpc('admin_bao_cao_san_pham', { p_hanh_dong: args.hanh_dong || 'ban_chay', p_khoang: khoang });
    if (name === 'bao_cao_khach_hang') return rpc('admin_bao_cao_khach_hang', { p_hanh_dong: args.hanh_dong || 'tong_quan', p_khoang: khoang });
    if (name === 'bao_cao_khuyen_mai') return rpc('admin_bao_cao_khuyen_mai', { p_hanh_dong: args.hanh_dong || 'voucher' });
    return Promise.resolve({ loi: 'Không rõ tool "' + name + '".' });
  }
  function toolStatus(name) {
    if (name === 'bao_cao_kinh_doanh') return 'Đang tổng hợp doanh thu…';
    if (name === 'bao_cao_san_pham') return 'Đang tổng hợp dữ liệu sản phẩm…';
    if (name === 'bao_cao_khach_hang') return 'Đang tổng hợp dữ liệu khách hàng…';
    if (name === 'bao_cao_khuyen_mai') return 'Đang tổng hợp hiệu quả khuyến mãi…';
    return 'Đang xử lý…';
  }

  // ── Escape + markdown mini ──
  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function renderMarkdownMini(raw) {
    var lines = escapeHtml(raw).split('\n'), html = '', inList = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i], m = line.match(/^[-*]\s+(.*)$/);
      if (m) { if (!inList) { html += '<ul>'; inList = true; } html += '<li>' + m[1].replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</li>'; }
      else { if (inList) { html += '</ul>'; inList = false; } if (line.trim() === '') { html += '<br>'; continue; } html += '<p>' + line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</p>'; }
    }
    if (inList) html += '</ul>';
    return html;
  }

  var apiHistory = [];
  var displayMessages = [];
  var msgSeq = 0;
  var messagesEl, inputEl, sendBtn, chipsEl, panel, toggleBtn;

  // ── Lưu/khôi phục hội thoại theo phiên tab (chuyển trang admin không mất) ──
  function saveState() {
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ api: apiHistory, disp: displayMessages, seq: msgSeq })); } catch (e) {}
  }
  function loadState() {
    try {
      var s = JSON.parse(sessionStorage.getItem(STORAGE_KEY) || 'null');
      if (s && Array.isArray(s.api) && Array.isArray(s.disp)) { apiHistory = s.api; displayMessages = s.disp; msgSeq = s.seq || displayMessages.length; return true; }
    } catch (e) {}
    return false;
  }

  function scrollBottom() { if (messagesEl) messagesEl.scrollTop = messagesEl.scrollHeight; }
  function renderOne(m) {
    if (m.type === 'typing') {
      return '<div class="ai-chat-msg ai-chat-msg--bot" data-mid="' + m.id + '"><span class="ai-chat-msg__avatar">' + GEAR_XS + '</span>'
        + '<span class="ai-chat-msg__bubble">' + (m.label ? '<span class="ai-chat-typing"><span></span><span></span><span></span></span>' : '') + '</span></div>';
    }
    if (m.role === 'user') return '<div class="ai-chat-msg ai-chat-msg--user" data-mid="' + m.id + '"><span class="ai-chat-msg__bubble">' + escapeHtml(m.text) + '</span></div>';
    return '<div class="ai-chat-msg ai-chat-msg--bot" data-mid="' + m.id + '"><span class="ai-chat-msg__avatar">' + GEAR_XS + '</span><span class="ai-chat-msg__bubble">' + renderMarkdownMini(m.text) + '</span></div>';
  }
  function renderAll() { if (messagesEl) { messagesEl.innerHTML = displayMessages.map(renderOne).join(''); scrollBottom(); } }
  function appendDisplay(m) { m.id = 'm' + (++msgSeq); displayMessages.push(m); renderAll(); return m.id; }
  function updateDisplay(id, patch) { var m = displayMessages.find(function (x) { return x.id === id; }); if (m) { Object.assign(m, patch); renderAll(); } }
  function removeDisplay(id) { displayMessages = displayMessages.filter(function (x) { return x.id !== id; }); renderAll(); }

  function setBusy(busy) {
    if (inputEl) inputEl.disabled = busy;
    if (sendBtn) sendBtn.disabled = busy || !(inputEl && inputEl.value.trim());
    if (chipsEl) chipsEl.querySelectorAll('button').forEach(function (b) { b.disabled = busy; });
  }

  function postRelay(contents, signal) {
    return fetch(RELAY_URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ contents: contents }), signal: signal })
      .then(function (res) { return res.json().catch(function () { return {}; }).then(function (json) { if (!res.ok) throw new Error(json.error || ('Relay lỗi HTTP ' + res.status)); return json; }); });
  }

  function sendMessage(userText) {
    userText = (userText || '').trim();
    if (!userText) return;
    appendDisplay({ role: 'user', text: userText });
    apiHistory.push({ role: 'user', parts: [{ text: userText }] });
    if (inputEl) inputEl.value = '';
    setBusy(true);
    var typingId = appendDisplay({ type: 'typing', label: 'Đang xử lý…' });
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, TONG_TIMEOUT_MS);
    var round = 0;

    function step() {
      return postRelay(apiHistory, controller.signal).then(function (res) {
        if (Array.isArray(res.serverTurns) && res.serverTurns.length) apiHistory.push.apply(apiHistory, res.serverTurns);
        var parts = (res.candidates && res.candidates[0] && res.candidates[0].content && res.candidates[0].content.parts) || [];
        var callPart = null;
        for (var i = 0; i < parts.length; i++) { if (parts[i].functionCall) { callPart = parts[i]; break; } }
        var isLast = round >= CLIENT_TOOL_ROUND_LIMIT - 1;

        if (!callPart || isLast) {
          removeDisplay(typingId);
          var text = parts.filter(function (p) { return p.text; }).map(function (p) { return p.text; }).join('\n')
            || (callPart ? 'Yêu cầu này cần nhiều bước hơn mức cho phép — thử hỏi gọn hơn nhé.' : 'Chưa có câu trả lời phù hợp.');
          appendDisplay({ role: 'bot', text: text });
          if (parts.length) {
            apiHistory.push({ role: 'model', parts: parts });
            if (callPart) apiHistory.push({ role: 'user', parts: [{ functionResponse: { name: callPart.functionCall.name, response: { loi: 'Đã vượt giới hạn số vòng gọi tool.' }, id: callPart.functionCall.id } }] });
          }
          saveState();
          return;
        }
        apiHistory.push({ role: 'model', parts: parts });
        var fc = callPart.functionCall;
        updateDisplay(typingId, { type: 'typing', label: toolStatus(fc.name) });
        return Promise.resolve(chayToolAdmin(fc.name, fc.args)).catch(function (e) { return { loi: 'Không chạy được tool (' + e.message + ')' }; })
          .then(function (ketQua) {
            apiHistory.push({ role: 'user', parts: [{ functionResponse: { name: fc.name, response: ketQua, id: fc.id } }] });
            round++;
            return step();
          });
      });
    }

    step().catch(function (e) {
      removeDisplay(typingId);
      if (e.name === 'AbortError') {
        var last = apiHistory[apiHistory.length - 1];
        if (last && last.role === 'user' && last.parts && last.parts[0] && last.parts[0].text === userText) apiHistory.pop();
        appendDisplay({ role: 'bot', text: '⏱️ Phản hồi mất quá lâu nên đã tự huỷ. Bạn gửi lại giúp nhé.' });
      } else {
        appendDisplay({ role: 'bot', text: 'Có lỗi khi kết nối AI (' + e.message + '). Thử lại sau nhé.' });
      }
      saveState();
    }).then(function () { clearTimeout(timer); setBusy(false); });
  }

  function build() {
    var floatCta = document.querySelector('.float-cta');
    if (!floatCta || document.getElementById('ai-chat-toggle')) return;

    floatCta.insertAdjacentHTML('beforeend', TOGGLE_HTML);
    floatCta.insertAdjacentHTML('afterend', PANEL_HTML);

    toggleBtn = document.getElementById('ai-chat-toggle');
    panel = document.getElementById('ai-chat-panel');
    messagesEl = document.getElementById('ai-chat-messages');
    inputEl = document.getElementById('ai-chat-input');
    sendBtn = document.getElementById('ai-chat-send');
    chipsEl = document.getElementById('ai-chat-suggestions');
    var closeBtn = document.getElementById('ai-chat-close');
    if (!toggleBtn || !panel) return;

    function setOpen(open) {
      toggleBtn.classList.toggle('is-open', open);
      panel.classList.toggle('is-open', open);
      floatCta.classList.toggle('is-chat-open', open);
      toggleBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
      if (open && inputEl) inputEl.focus();
    }
    toggleBtn.addEventListener('click', function () { setOpen(!panel.classList.contains('is-open')); });
    if (closeBtn) closeBtn.addEventListener('click', function () { setOpen(false); });

    if (inputEl) {
      inputEl.addEventListener('input', function () { if (sendBtn) sendBtn.disabled = !inputEl.value.trim(); });
      inputEl.addEventListener('keydown', function (e) { if (e.key === 'Enter') { e.preventDefault(); if (sendBtn && !sendBtn.disabled) sendMessage(inputEl.value); } });
    }
    if (sendBtn) { sendBtn.disabled = true; sendBtn.addEventListener('click', function () { if (!sendBtn.disabled) sendMessage(inputEl.value); }); }
    if (chipsEl) {
      // Khôi phục lựa chọn tắt thanh gợi ý (localStorage).
      try { if (localStorage.getItem('yd-admin-chips-hidden') === '1') chipsEl.classList.add('is-hidden'); } catch (e) {}
      chipsEl.addEventListener('click', function (e) {
        var hideBtn = e.target.closest('[data-hide-suggestions]');
        if (hideBtn) {
          chipsEl.classList.add('is-hidden');
          try { localStorage.setItem('yd-admin-chips-hidden', '1'); } catch (e2) {}
          return;
        }
        var b = e.target.closest('button[data-prompt]');
        if (b) sendMessage(b.dataset.prompt);
      });
    }

    // Khôi phục hội thoại phiên trước (chuyển trang) hoặc chào mới.
    if (loadState() && displayMessages.length) renderAll();
    else appendDisplay({ role: 'bot', text: 'Chào chị chủ 👋 Em là trợ lý phân tích kinh doanh. Em **chỉ đọc** số liệu thật (doanh thu, đơn, sản phẩm, khách, khuyến mãi) để báo cáo. Chị cần xem gì ạ?' });
  }

  // ── GUARD: chỉ dựng widget khi ĐÚNG là admin (xác thực lại phiên thật +
  //    profiles.role, KHÔNG tin localStorage). ──
  function init() {
    if (!document.querySelector('.float-cta')) return;
    if (typeof getSupabase !== 'function') return;
    var sb = getSupabase();
    sb.auth.getSession().then(function (r) {
      var session = r && r.data && r.data.session;
      if (!session) return; // chưa đăng nhập → không hiện
      return sb.from('profiles').select('role').eq('id', session.user.id).single().then(function (p) {
        if (p && p.data && p.data.role === 'admin') build();
      });
    }).catch(function () { /* lỗi mạng/xác thực → im lặng, không dựng */ });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
