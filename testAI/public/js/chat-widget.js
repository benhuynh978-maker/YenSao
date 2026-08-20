// ============================================================
// CLIENT CHAT LOGIC — vòng lặp tool-calling thật, gọi relay server thật
// (/api/chat), theo đúng AI-Chat-Nhung-Co-Tool.md. Nhóm A: tool đọc
// Supabase THẬT (san_pham/flash_sale/thong_tin_cua_hang), không giả lập nữa.
// ============================================================
import { chayToolClient } from './tools.js';

const CLIENT_TOOL_ROUND_LIMIT = 3; // chốt chặn vòng lặp tool phía CLIENT (độc lập với chốt chặn phía server)

// ── Hai lịch sử tách biệt (mục 4 tài liệu) ──
const apiHistory = [];      // gửi lên relay mỗi lượt — đúng khuôn Gemini contents
let displayMessages = [];   // chỉ để vẽ UI — có thêm trạng thái tạm (typing, tool-status, card)
let msgSeq = 0;

// ── DOM refs ──
const toggleBtn = document.getElementById('chat-toggle');
const panel = document.getElementById('chat-panel');
const closeBtn = document.getElementById('chat-close');
const messagesEl = document.getElementById('chat-messages');
const inputEl = document.getElementById('chat-input');
const sendBtn = document.getElementById('chat-send');
const chipsEl = document.getElementById('chat-suggestions');

// ── Escape + markdown tối giản (mục 9 tài liệu) ──
function escapeHtml(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
// Escape TRƯỚC, chỉ sinh thêm đúng 2 loại thẻ an toàn (<strong>, <ul><li>) —
// không bao giờ chèn thẳng HTML thô từ user/model vào DOM.
function renderMarkdownMini(raw) {
  const lines = escapeHtml(raw).split('\n');
  let html = '';
  let inList = false;
  for (const line of lines) {
    const bulletMatch = line.match(/^[-*]\s+(.*)$/); // đòi có khoảng trắng sau -/* (mục 9 lưu ý)
    if (bulletMatch) {
      if (!inList) { html += '<ul>'; inList = true; }
      html += '<li>' + bulletMatch[1].replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</li>';
    } else {
      if (inList) { html += '</ul>'; inList = false; }
      if (line.trim() === '') { html += '<br>'; continue; }
      html += '<p>' + line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>') + '</p>';
    }
  }
  if (inList) html += '</ul>';
  return html;
}
function fmtVND(n) { return Number(n || 0).toLocaleString('vi-VN') + 'đ'; }

// ── BOX DỰNG SẴN (phí ship / chính sách) — nội dung CỐ ĐỊNH, không qua AI,
// không qua tool (đúng quyết định: 2 mảng thông tin này không có trong
// Supabase, đưa vào prompt cũng chỉ là "học vẹt" dễ lệch khi chính sách đổi).
// Nội dung phí ship khớp đúng hằng số thật ở dat-hang.html (FREE_SHIP_
// THRESHOLD=500000, FLAT_SHIPPING_FEE=35000). Nội dung chính sách tóm tắt từ
// chinh-sach.html#doi-tra (mục Đổi Trả & Hoàn Tiền) của site chính.
const CANNED_BOXES = {
  'phi-van-chuyen': '🚚 **Phí vận chuyển**\n'
    + '- Miễn phí vận chuyển cho đơn từ 500.000đ.\n'
    + '- Đơn dưới 500.000đ: phí vận chuyển cố định 35.000đ.',
  'chinh-sach-doi-tra': '🔄 **Chính sách đổi trả & hoàn tiền**\n'
    + '- Được hỗ trợ nếu: hàng lỗi/hỏng do vận chuyển, giao sai sản phẩm/số lượng, không đạt chất lượng cam kết, hoặc hàng giả.\n'
    + '- Không hỗ trợ nếu: đổi ý sau khi nhận hàng, đã mở bao bì/sử dụng, quá 7 ngày kể từ khi nhận hàng, hoặc hư hỏng do bảo quản sai.\n'
    + '- Quy trình: liên hệ hotline/Zalo trong 7 ngày kèm ảnh/video + mã đơn → duyệt trong 24h → đổi hàng mới (3–5 ngày) hoặc hoàn tiền 100% (trong 2 ngày làm việc).',
};

// ── Render UI từ displayMessages ──
function scrollToBottom() { messagesEl.scrollTop = messagesEl.scrollHeight; }

function renderAll() {
  messagesEl.innerHTML = displayMessages.map(renderOne).join('');
  scrollToBottom();
}
function productCardHtml(sp) {
  return '<div class="product-card-mini">'
    + '<div class="product-card-mini__name">' + escapeHtml(sp.name) + '</div>'
    + '<div class="product-card-mini__price">' + fmtVND(sp.price)
    + (sp.old_price && sp.old_price > sp.price ? ' <span style="text-decoration:line-through">' + fmtVND(sp.old_price) + '</span>' : '')
    + (sp.category ? ' <span>· ' + escapeHtml(sp.category) + '</span>' : '') + '</div>'
    + (sp.description ? '<div class="product-card-mini__desc">' + escapeHtml(sp.description) + '</div>' : '')
    + (typeof sp.stock === 'number' ? '<div class="product-card-mini__desc">' + (sp.stock > 0 ? 'Còn hàng (' + sp.stock + ')' : 'Tạm hết hàng') + '</div>' : '')
    + '</div>';
}
function renderOne(m) {
  if (m.type === 'typing') {
    return '<div class="msg msg--bot" data-mid="' + m.id + '">'
      + '<span class="msg__avatar">🐦</span>'
      + '<span class="msg__bubble msg__bubble--typing">'
      + (m.label ? '<span class="msg__typing-label">' + escapeHtml(m.label) + '</span>' : '')
      + '<span class="typing-dots"><span></span><span></span><span></span></span>'
      + '</span></div>';
  }
  if (m.type === 'products') {
    if (!m.products.length) {
      return '<div class="msg msg--bot" data-mid="' + m.id + '"><span class="msg__avatar">🐦</span><span class="msg__bubble">Không tìm thấy sản phẩm nào khớp.</span></div>';
    }
    const cards = m.products.map(productCardHtml).join('');
    return '<div class="msg msg--bot" data-mid="' + m.id + '"><span class="msg__avatar">🐦</span><span class="msg__bubble msg__bubble--cards">' + cards + '</span></div>';
  }
  if (m.role === 'user') {
    return '<div class="msg msg--user" data-mid="' + m.id + '"><span class="msg__bubble">' + escapeHtml(m.text) + '</span></div>';
  }
  return '<div class="msg msg--bot" data-mid="' + m.id + '"><span class="msg__avatar">🐦</span><span class="msg__bubble">' + renderMarkdownMini(m.text) + '</span></div>';
}
function appendDisplay(m) {
  m.id = 'm' + (++msgSeq);
  displayMessages.push(m);
  renderAll();
  return m.id;
}
function updateDisplay(id, patch) {
  const m = displayMessages.find(x => x.id === id);
  if (m) { Object.assign(m, patch); renderAll(); }
}
function removeDisplay(id) {
  displayMessages = displayMessages.filter(x => x.id !== id);
  renderAll();
}

// ── Gọi relay server — nhận "signal" để có thể bị huỷ khi chạm trần thời
// gian chờ tổng (xem TỔNG_TIMEOUT_MS trong sendMessage bên dưới). ──
async function postRelay(contents, signal) {
  const res = await fetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ contents }),
    signal,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json.error || ('Relay lỗi HTTP ' + res.status));
  return json;
}

function toolStatusLabel(name) {
  if (name === 'san_pham') return 'Đang tra cứu sản phẩm…';
  if (name === 'flash_sale') return 'Đang kiểm tra khuyến mãi…';
  if (name === 'thong_tin_cua_hang') return 'Đang lấy thông tin cửa hàng…';
  return 'Đang xử lý…';
}

// ── Trạng thái khoá input khi đang chờ (mục 9 tài liệu) ──
function setBusy(busy) {
  inputEl.disabled = busy;
  sendBtn.disabled = busy || !inputEl.value.trim();
  chipsEl.querySelectorAll('button').forEach(b => { b.disabled = busy; });
}

// Trần thời gian chờ TỔNG cho cả 1 lượt hỏi (có thể gồm nhiều vòng gọi tool
// cộng dồn) — đo thật với model hiện tại chỉ ~0.7-1s/vòng, nên 40s đã dư dả
// gấp hàng chục lần cho trường hợp chậm bất thường. Hết giờ → TỰ HUỶ request
// đang treo (AbortController) + báo ngay "thử lại", không để khách kẹt ở
// "đang gõ..." vô thời hạn.
const TONG_TIMEOUT_MS = 40000;

// ── Vòng lặp tool-calling phía CLIENT (mục 3 tài liệu, có chốt chặn vòng) ──
async function sendMessage(userText) {
  userText = userText.trim();
  if (!userText) return;

  appendDisplay({ role: 'user', text: userText });
  apiHistory.push({ role: 'user', parts: [{ text: userText }] });
  inputEl.value = '';
  autoGrow();
  setBusy(true);

  const typingId = appendDisplay({ type: 'typing' });
  const controller = new AbortController();
  const tongTimer = setTimeout(() => controller.abort(), TONG_TIMEOUT_MS);

  try {
    for (let round = 0; round < CLIENT_TOOL_ROUND_LIMIT; round++) {
      const res = await postRelay(apiHistory, controller.signal);

      // Lượt server đã tự giải quyết tool "bí mật" (Nhóm B, hiện chưa có tool
      // nào) — nối vào lịch sử API của client để không bị lệch mạch nếu sau
      // này có tool server. Giữ nguyên cơ chế dù mảng luôn rỗng lúc này.
      if (Array.isArray(res.serverTurns) && res.serverTurns.length) {
        apiHistory.push(...res.serverTurns);
      }

      const parts = (res.candidates && res.candidates[0] && res.candidates[0].content && res.candidates[0].content.parts) || [];
      const callPart = parts.find(p => p.functionCall);
      const isLastRound = round >= CLIENT_TOOL_ROUND_LIMIT - 1;

      if (!callPart || isLastRound) {
        removeDisplay(typingId);
        const text = parts.filter(p => p.text).map(p => p.text).join('\n')
          || (callPart ? 'Xin lỗi, yêu cầu này cần nhiều bước xử lý hơn mức cho phép — bạn hỏi lại gọn hơn giúp mình nhé.' : 'Xin lỗi, tôi chưa có câu trả lời phù hợp lúc này.');
        appendDisplay({ role: 'bot', text });
        if (parts.length) {
          apiHistory.push({ role: 'model', parts });
          // Nếu bail ra vì chạm trần vòng lặp mà VẪN còn 1 functionCall chưa
          // giải quyết, phải "chốt" nó bằng 1 functionResponse giả (báo lỗi
          // vượt giới hạn) — nếu không, lượt "model" có functionCall mồ côi
          // sẽ làm hỏng lịch sử, khiến MỌI tin nhắn sau đó trong phiên bị
          // Gemini từ chối (lỗi 400 → relay 502).
          if (callPart) {
            apiHistory.push({
              role: 'user',
              parts: [{ functionResponse: { name: callPart.functionCall.name, response: { loi: 'Đã vượt giới hạn số vòng gọi tool cho phép.' }, ...(callPart.functionCall.id ? { id: callPart.functionCall.id } : {}) } }],
            });
          }
        }
        break;
      }

      // Có tool CLIENT cần chạy — lưu lượt model (yêu cầu gọi tool) trước.
      apiHistory.push({ role: 'model', parts });
      updateDisplay(typingId, { type: 'typing', label: toolStatusLabel(callPart.functionCall.name) });

      const { name, args, id } = callPart.functionCall;
      let ketQua;
      try {
        ketQua = await chayToolClient(name, args);
        if (name === 'san_pham' && ketQua && Array.isArray(ketQua.san_pham)) {
          appendDisplay({ type: 'products', products: ketQua.san_pham });
        } else if (name === 'san_pham' && ketQua && ketQua.san_pham && !Array.isArray(ketQua.san_pham)) {
          appendDisplay({ type: 'products', products: [ketQua.san_pham] });
        }
      } catch (e) {
        ketQua = { loi: 'Không chạy được tool (' + e.message + ')' };
      }
      apiHistory.push({ role: 'user', parts: [{ functionResponse: { name, response: ketQua, ...(id ? { id } : {}) } }] });
    }
  } catch (e) {
    removeDisplay(typingId);
    if (e.name === 'AbortError') {
      // Chạm trần TONG_TIMEOUT_MS — request đang treo đã bị tự huỷ. Loại bỏ
      // luôn lượt "user" vừa đẩy vào apiHistory nếu nó chưa có phản hồi nào
      // đi kèm, tránh lịch sử API bị lệch mạch ở lần gửi tiếp theo.
      const last = apiHistory[apiHistory.length - 1];
      if (last && last.role === 'user' && last.parts && last.parts[0] && last.parts[0].text === userText) {
        apiHistory.pop();
      }
      appendDisplay({ role: 'bot', text: '⏱️ Phản hồi mất quá lâu nên đã tự huỷ. Bạn bấm gửi lại câu hỏi giúp mình nhé!' });
    } else {
      appendDisplay({ role: 'bot', text: 'Xin lỗi, có lỗi khi kết nối AI (' + e.message + '). Bạn thử lại sau nhé.' });
    }
  } finally {
    clearTimeout(tongTimer);
    setBusy(false);
  }
}

// ── Textarea tự giãn theo chữ, có trần (mục 9 tài liệu) ──
const INPUT_MAX_HEIGHT = 120;
function autoGrow() {
  inputEl.style.height = 'auto';
  inputEl.style.height = Math.min(inputEl.scrollHeight, INPUT_MAX_HEIGHT) + 'px';
}

// ── Wiring ──
function setOpen(open) {
  toggleBtn.classList.toggle('is-open', open);
  panel.classList.toggle('is-open', open);
  toggleBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
  if (open) inputEl.focus();
}
toggleBtn.addEventListener('click', () => setOpen(!panel.classList.contains('is-open')));
closeBtn.addEventListener('click', () => setOpen(false));

inputEl.addEventListener('input', () => { autoGrow(); sendBtn.disabled = !inputEl.value.trim(); });
inputEl.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    if (!sendBtn.disabled) sendMessage(inputEl.value);
  }
});
sendBtn.addEventListener('click', () => { if (!sendBtn.disabled) sendMessage(inputEl.value); });
chipsEl.addEventListener('click', (e) => {
  const boxBtn = e.target.closest('button[data-box]');
  if (boxBtn) {
    // Box dựng sẵn — hiện thẳng, KHÔNG gọi AI/tool, KHÔNG đụng apiHistory.
    appendDisplay({ role: 'user', text: boxBtn.textContent });
    appendDisplay({ role: 'bot', text: CANNED_BOXES[boxBtn.dataset.box] || 'Chưa có nội dung.' });
    return;
  }
  const promptBtn = e.target.closest('button[data-prompt]');
  if (promptBtn) sendMessage(promptBtn.dataset.prompt);
});

// ── Lời chào mở đầu — chỉ ở displayHistory (UI), KHÔNG đẩy vào apiHistory vì
// chưa có lượt user nào để "trả lời", đúng nguyên tắc tách 2 lịch sử. ──
appendDisplay({ role: 'bot', text: 'Xin chào! 👋 Em là trợ lý AI của Yến Duyên — dữ liệu sản phẩm/khuyến mãi/thông tin cửa hàng em trả lời đều lấy **thật** từ hệ thống. Anh/chị cần hỗ trợ gì ạ?' });
sendBtn.disabled = true;
