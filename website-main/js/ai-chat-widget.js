// ============================================================
// AI CHAT WIDGET (KHÁCH HÀNG) — bản THẬT, dùng chung cho các trang khách.
// Script thường (KHÔNG ES module — ràng buộc file://). Tự chèn nút chat vào
// .float-cta có sẵn, chạy vòng lặp function-calling thật qua relay /api/chat,
// tool đọc Supabase THẬT (chỉ dữ liệu công khai: sản phẩm/flash sale/thông tin
// cửa hàng). Cần supabase-client.js (getSupabase) nạp TRƯỚC file này.
//
// CÁCH DÙNG ở 1 trang: <link css/ai-chat.css> + có sẵn <div class="float-cta">
// + <script js/ai-chat-widget.js>. Không có .float-cta thì tự bỏ qua.
//
// RELAY: dùng đường dẫn TƯƠNG ĐỐI /api/chat — hoạt động khi trang được relay
// (ai-chat/server.js) serve cùng origin (test local). KHI DEPLOY THẬT mà web
// và relay khác origin: đổi RELAY_URL thành URL tuyệt đối của relay.
// ============================================================
(function () {
  var RELAY_URL = '/api/chat';
  var CLIENT_TOOL_ROUND_LIMIT = 3;   // trần vòng gọi tool phía client
  var TONG_TIMEOUT_MS = 40000;       // trần thời gian cho cả 1 lượt hỏi

  // ── Icons ──
  var BIRD = '<svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var BIRD_SM = '<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var BIRD_XS = '<svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var CLOSE = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var CLOSE_SM = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var SEND = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>';

  var TOGGLE_HTML =
    '<button class="ai-chat-toggle" id="ai-chat-toggle" aria-label="Mở chat hỗ trợ" aria-expanded="false" aria-controls="ai-chat-panel">'
    + '<span class="ai-chat-toggle__icon">' + BIRD + '</span>'
    + '<span class="ai-chat-toggle__close">' + CLOSE + '</span>'
    + '<span class="ai-chat-toggle__dot" aria-hidden="true"></span>'
    + '<span>Chat AI</span>'
    + '</button>';

  var PANEL_HTML =
    '<div class="ai-chat-panel" id="ai-chat-panel" role="dialog" aria-modal="false" aria-label="Chat hỗ trợ Yến Duyên">'
    + '<div class="ai-chat-panel__header">'
    + '<span class="ai-chat-panel__avatar">' + BIRD_SM + '</span>'
    + '<span class="ai-chat-panel__title">'
    + '<span class="ai-chat-panel__name">Yến Duyên AI</span>'
    + '<span class="ai-chat-panel__status">Đang hoạt động</span>'
    + '</span>'
    + '<button class="ai-chat-panel__close" id="ai-chat-close" aria-label="Đóng chat">' + CLOSE_SM + '</button>'
    + '</div>'
    + '<div class="ai-chat-panel__messages" id="ai-chat-messages"></div>'
    + '<div class="ai-chat-panel__suggestions" id="ai-chat-suggestions">'
    + '<button type="button" class="ai-chat-chip" data-prompt="Bên mình có mấy loại yến sào, giá thế nào?">Giá yến sào</button>'
    + '<button type="button" class="ai-chat-chip" data-prompt="Đang có chương trình khuyến mãi/flash sale gì không?">Đang sale gì?</button>'
    + '<button type="button" class="ai-chat-chip" data-box="phi-van-chuyen">Phí vận chuyển</button>'
    + '<button type="button" class="ai-chat-chip" data-box="chinh-sach-doi-tra">Chính sách đổi trả</button>'
    + '<button type="button" class="ai-chat-suggestions__hide" data-hide-suggestions aria-label="Ẩn gợi ý">Ẩn ✕</button>'
    + '</div>'
    + '<div class="ai-chat-panel__input-row">'
    + '<input type="text" class="ai-chat-panel__input" id="ai-chat-input" placeholder="Nhập câu hỏi của bạn..." aria-label="Nhập tin nhắn">'
    + '<button type="button" class="ai-chat-panel__send" id="ai-chat-send" aria-label="Gửi tin nhắn">' + SEND + '</button>'
    + '</div>'
    + '</div>';

  // ══════════════════════════════════════════════════════════
  // 3 TOOL CHẠY Ở CLIENT — Supabase THẬT (chỉ đọc dữ liệu công khai).
  // Khớp khai báo CLIENT_TOOL_DECLARATIONS trong ai-chat/server.js.
  // ══════════════════════════════════════════════════════════
  function san_pham(args) {
    var hanhDong = args && args.hanh_dong;
    var sb = getSupabase();
    if (hanhDong === 'chi_tiet') {
      var id = args && args.id;
      if (!id) return Promise.resolve({ loi: 'Thiếu id sản phẩm.' });
      return sb.from('products').select('id,name,price,old_price,category,description,stock,image_url,badge')
        .eq('id', id).eq('is_active', true).maybeSingle()
        .then(function (res) {
          if (res.error) return { loi: res.error.message };
          if (!res.data) return { loi: 'Không tìm thấy sản phẩm với id này (có thể đã ngừng bán).' };
          return { san_pham: res.data };
        });
    }
    var tuKhoa = (args && args.tu_khoa || '').trim();
    var giaToiDa = args && args.gia_toi_da;
    var q = sb.from('products').select('id,name,price,old_price,category,stock,image_url').eq('is_active', true);
    if (tuKhoa) {
      var kw = '%' + tuKhoa.replace(/[%,()]/g, '') + '%';
      q = q.or('name.ilike.' + kw + ',category.ilike.' + kw + ',description.ilike.' + kw);
    }
    if (giaToiDa) q = q.lte('price', Number(giaToiDa));
    q = q.order('sold_count', { ascending: false }).limit(8);
    return q.then(function (res) {
      if (res.error) return { loi: res.error.message };
      return { so_luong_tim_thay: (res.data || []).length, san_pham: res.data || [] };
    });
  }

  function flash_sale() {
    var sb = getSupabase();
    return sb.from('flash_sales').select('*').eq('is_active', true).order('start_at', { ascending: true })
      .then(function (res) {
        if (res.error) return { loi: res.error.message };
        var rows = res.data || [];
        if (!rows.length) return { trang_thai: 'khong_co' };
        var now = Date.now();
        var active = rows.filter(function (fs) { return new Date(fs.start_at).getTime() <= now && new Date(fs.end_at).getTime() >= now; });
        var chosen, trangThai;
        if (active.length) { chosen = active[0]; trangThai = 'dang_dien_ra'; }
        else {
          var upcoming = rows.filter(function (fs) { return new Date(fs.start_at).getTime() > now; })
            .sort(function (a, b) { return new Date(a.start_at) - new Date(b.start_at); });
          if (!upcoming.length) return { trang_thai: 'khong_co' };
          chosen = upcoming[0]; trangThai = 'sap_dien_ra';
        }
        return sb.from('flash_sale_items').select('*').eq('flash_sale_id', chosen.id).then(function (itemsRes) {
          if (itemsRes.error) return { loi: itemsRes.error.message };
          var items = itemsRes.data || [];
          if (!items.length) return { trang_thai: 'khong_co' };
          var ids = items.map(function (it) { return it.product_id; });
          return sb.from('products').select('id,name,price,image_url').in('id', ids).eq('is_active', true).then(function (prodRes) {
            if (prodRes.error) return { loi: prodRes.error.message };
            var pmap = {};
            (prodRes.data || []).forEach(function (p) { pmap[p.id] = p; });
            var sanPham = items.map(function (it) {
              var p = pmap[it.product_id];
              if (!p) return null;
              var giam = p.price > it.sale_price ? Math.round((1 - it.sale_price / p.price) * 100) : 0;
              return { ten: p.name, gia_goc: p.price, gia_sale: it.sale_price, giam_phan_tram: giam, con_lai: Math.max(0, it.stock_limit - it.sold_count) };
            }).filter(Boolean);
            return { trang_thai: trangThai, ten_dot: chosen.name, bat_dau: chosen.start_at, ket_thuc: chosen.end_at, san_pham: sanPham };
          });
        });
      });
  }

  function thong_tin_cua_hang() {
    var sb = getSupabase();
    return sb.from('site_settings').select('shop_name,phone,zalo_phone,facebook_url,email,address').limit(1).maybeSingle()
      .then(function (res) {
        if (res.error) return { loi: res.error.message };
        if (!res.data) return { loi: 'Chưa có thông tin cửa hàng.' };
        return res.data;
      });
  }

  function chayToolClient(name, args) {
    if (name === 'san_pham') return san_pham(args || {});
    if (name === 'flash_sale') return flash_sale();
    if (name === 'thong_tin_cua_hang') return thong_tin_cua_hang();
    return Promise.resolve({ loi: 'Không rõ tool "' + name + '".' });
  }

  // ── BOX DỰNG SẴN — nội dung CỐ ĐỊNH, KHÔNG qua AI/tool (phí ship + chính
  // sách không nằm trong Supabase). Khớp nội dung thật ở dat-hang/chinh-sach. ──
  var CANNED_BOXES = {
    'phi-van-chuyen': '🚚 **Phí vận chuyển**\n'
      + '- Miễn phí vận chuyển cho đơn từ 500.000đ.\n'
      + '- Đơn dưới 500.000đ: phí vận chuyển cố định 35.000đ.',
    'chinh-sach-doi-tra': '🔄 **Chính sách đổi trả & hoàn tiền**\n'
      + '- Được hỗ trợ nếu: hàng lỗi/hỏng do vận chuyển, giao sai sản phẩm/số lượng, không đạt chất lượng cam kết, hoặc hàng giả.\n'
      + '- Không hỗ trợ nếu: đổi ý sau khi nhận hàng, đã mở bao bì/sử dụng, quá 7 ngày kể từ khi nhận hàng, hoặc hư hỏng do bảo quản sai.\n'
      + '- Quy trình: liên hệ hotline/Zalo trong 7 ngày kèm ảnh/video + mã đơn → duyệt trong 24h → đổi hàng mới (3–5 ngày) hoặc hoàn tiền 100% (trong 2 ngày làm việc).',
  };

  // ── Escape + markdown tối giản (chống XSS: escape TRƯỚC, chỉ sinh <strong>/<ul>) ──
  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }
  function renderMarkdownMini(raw) {
    var lines = escapeHtml(raw).split('\n');
    var html = '', inList = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var m = line.match(/^[-*]\s+(.*)$/);
      if (m) {
        if (!inList) { html += '<ul>'; inList = true; }
        html += '<li>' + m[1].replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</li>';
      } else {
        if (inList) { html += '</ul>'; inList = false; }
        if (line.trim() === '') { html += '<br>'; continue; }
        html += '<p>' + line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</p>';
      }
    }
    if (inList) html += '</ul>';
    return html;
  }

  // ── Trạng thái + render ──
  var apiHistory = [];       // gửi lên relay — đúng khuôn Gemini contents
  var displayMessages = [];  // vẽ UI
  var msgSeq = 0;
  var messagesEl, inputEl, sendBtn, chipsEl, panel, toggleBtn;

  function scrollBottom() { if (messagesEl) messagesEl.scrollTop = messagesEl.scrollHeight; }

  function renderOne(m) {
    if (m.type === 'typing') {
      return '<div class="ai-chat-msg ai-chat-msg--bot" data-mid="' + m.id + '">'
        + '<span class="ai-chat-msg__avatar">' + BIRD_XS + '</span>'
        + '<span class="ai-chat-msg__bubble"><span class="ai-chat-typing" aria-label="Đang soạn trả lời"><span></span><span></span><span></span></span></span></div>';
    }
    if (m.role === 'user') {
      return '<div class="ai-chat-msg ai-chat-msg--user" data-mid="' + m.id + '"><span class="ai-chat-msg__bubble">' + escapeHtml(m.text) + '</span></div>';
    }
    return '<div class="ai-chat-msg ai-chat-msg--bot" data-mid="' + m.id + '">'
      + '<span class="ai-chat-msg__avatar">' + BIRD_XS + '</span>'
      + '<span class="ai-chat-msg__bubble">' + renderMarkdownMini(m.text) + '</span></div>';
  }
  function renderAll() {
    if (!messagesEl) return;
    messagesEl.innerHTML = displayMessages.map(renderOne).join('');
    scrollBottom();
  }
  function appendDisplay(m) { m.id = 'm' + (++msgSeq); displayMessages.push(m); renderAll(); return m.id; }
  function removeDisplay(id) { displayMessages = displayMessages.filter(function (x) { return x.id !== id; }); renderAll(); }

  function setBusy(busy) {
    if (inputEl) inputEl.disabled = busy;
    if (sendBtn) sendBtn.disabled = busy || !(inputEl && inputEl.value.trim());
    if (chipsEl) chipsEl.querySelectorAll('button').forEach(function (b) { b.disabled = busy; });
  }

  function postRelay(contents, signal) {
    return fetch(RELAY_URL, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ contents: contents }), signal: signal,
    }).then(function (res) {
      return res.json().catch(function () { return {}; }).then(function (json) {
        if (!res.ok) throw new Error(json.error || ('Relay lỗi HTTP ' + res.status));
        return json;
      });
    });
  }

  // ── Vòng lặp tool-calling ──
  function sendMessage(userText) {
    userText = (userText || '').trim();
    if (!userText) return;
    appendDisplay({ role: 'user', text: userText });
    apiHistory.push({ role: 'user', parts: [{ text: userText }] });
    if (inputEl) inputEl.value = '';
    setBusy(true);
    var typingId = appendDisplay({ type: 'typing' });
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
            || (callPart ? 'Xin lỗi, câu này cần nhiều bước xử lý hơn mức cho phép — bạn hỏi lại gọn hơn giúp mình nhé.' : 'Xin lỗi, mình chưa có câu trả lời phù hợp lúc này.');
          appendDisplay({ role: 'bot', text: text });
          if (parts.length) {
            apiHistory.push({ role: 'model', parts: parts });
            if (callPart) {
              apiHistory.push({ role: 'user', parts: [{ functionResponse: { name: callPart.functionCall.name, response: { loi: 'Đã vượt giới hạn số vòng gọi tool cho phép.' }, id: callPart.functionCall.id } }] });
            }
          }
          return;
        }
        // Có tool client cần chạy
        apiHistory.push({ role: 'model', parts: parts });
        var fc = callPart.functionCall;
        return Promise.resolve(chayToolClient(fc.name, fc.args)).catch(function (e) {
          return { loi: 'Không chạy được tool (' + e.message + ')' };
        }).then(function (ketQua) {
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
        appendDisplay({ role: 'bot', text: '⏱️ Phản hồi mất quá lâu nên đã tự huỷ. Bạn bấm gửi lại câu hỏi giúp mình nhé!' });
      } else {
        appendDisplay({ role: 'bot', text: 'Xin lỗi, có lỗi khi kết nối AI (' + e.message + '). Bạn thử lại sau nhé.' });
      }
    }).then(function () {
      clearTimeout(timer);
      setBusy(false);
    });
  }

  function init() {
    var floatCta = document.querySelector('.float-cta');
    if (!floatCta || document.getElementById('ai-chat-toggle')) return;
    if (typeof getSupabase !== 'function') return; // cần Supabase để tool chạy

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
      toggleBtn.setAttribute('aria-label', open ? 'Đóng chat hỗ trợ' : 'Mở chat hỗ trợ');
      if (open && inputEl) inputEl.focus();
    }
    toggleBtn.addEventListener('click', function () { setOpen(!panel.classList.contains('is-open')); });
    if (closeBtn) closeBtn.addEventListener('click', function () { setOpen(false); });

    if (inputEl) {
      inputEl.addEventListener('input', function () { if (sendBtn) sendBtn.disabled = !inputEl.value.trim(); });
      inputEl.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); if (sendBtn && !sendBtn.disabled) sendMessage(inputEl.value); }
      });
    }
    if (sendBtn) { sendBtn.disabled = true; sendBtn.addEventListener('click', function () { if (!sendBtn.disabled) sendMessage(inputEl.value); }); }
    if (chipsEl) {
      // Khôi phục: nếu người dùng đã tắt thanh gợi ý lần trước → ẩn luôn.
      try { if (localStorage.getItem('yd-chat-chips-hidden') === '1') chipsEl.classList.add('is-hidden'); } catch (e) {}
      chipsEl.addEventListener('click', function (e) {
        var hideBtn = e.target.closest('[data-hide-suggestions]');
        if (hideBtn) {
          chipsEl.classList.add('is-hidden');
          try { localStorage.setItem('yd-chat-chips-hidden', '1'); } catch (e2) {}
          return;
        }
        var boxBtn = e.target.closest('button[data-box]');
        if (boxBtn) {
          appendDisplay({ role: 'user', text: boxBtn.textContent });
          appendDisplay({ role: 'bot', text: CANNED_BOXES[boxBtn.dataset.box] || 'Chưa có nội dung.' });
          return;
        }
        var pBtn = e.target.closest('button[data-prompt]');
        if (pBtn) sendMessage(pBtn.dataset.prompt);
      });
    }

    // Lời chào — chỉ ở UI, KHÔNG đẩy vào apiHistory (chưa có lượt user để "trả lời").
    appendDisplay({ role: 'bot', text: 'Xin chào! 👋 Em là trợ lý AI của Yến Duyên — thông tin sản phẩm/khuyến mãi/cửa hàng em trả lời đều lấy **thật** từ hệ thống. Anh/chị cần hỗ trợ gì ạ?' });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
