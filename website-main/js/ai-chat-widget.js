// ============================================================
// AI CHAT WIDGET — file DÙNG CHUNG cho nhiều trang khách, tránh phải copy
// HTML/JS widget vào từng file. BẢN MẪU GIAO DIỆN — chưa nối logic gửi/nhận
// AI thật, chỉ demo hiệu ứng mở/đóng + hiệu ứng "đang gõ".
//
// CÁCH DÙNG ở 1 trang mới:
//   1. Thêm <link rel="stylesheet" href="css/ai-chat.css"> trong <head>.
//   2. Đảm bảo trang đã có sẵn <div class="float-cta">...</div> (cụm nút
//      Gọi/Zalo/Facebook) — nút chat sẽ tự chèn vào làm item cuối cùng.
//   3. Thêm <script src="js/ai-chat-widget.js"></script> trước </body>.
// Không cần sửa gì thêm — script tự tìm .float-cta, tự chèn nút + khung chat,
// tự gắn sự kiện. Nếu trang không có .float-cta thì script tự bỏ qua, không
// báo lỗi (an toàn khi lỡ nhúng nhầm vào trang chưa có cụm nút).
// ============================================================
(function () {
  var BIRD_ICON = '<svg width="24" height="24" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var BIRD_ICON_SM = '<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var BIRD_ICON_XS = '<svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 14c3-6 8-8 9-8s6 2 9 8c-3-2-6-3-9-1-3-2-6-1-9 1z" fill="currentColor"/></svg>';
  var CLOSE_ICON = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var CLOSE_ICON_SM = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
  var SEND_ICON = '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>';

  var TOGGLE_HTML =
    '<!-- AI CHAT WIDGET — BẢN MẪU GIAO DIỆN, chèn tự động bởi js/ai-chat-widget.js -->'
    + '<button class="ai-chat-toggle" id="ai-chat-toggle" aria-label="Mở chat hỗ trợ" aria-expanded="false" aria-controls="ai-chat-panel">'
    + '<span class="ai-chat-toggle__icon">' + BIRD_ICON + '</span>'
    + '<span class="ai-chat-toggle__close">' + CLOSE_ICON + '</span>'
    + '<span class="ai-chat-toggle__dot" aria-hidden="true"></span>'
    + '<span>Chat AI</span>'
    + '</button>';

  var PANEL_HTML =
    '<div class="ai-chat-panel" id="ai-chat-panel" role="dialog" aria-modal="false" aria-label="Chat hỗ trợ Yến Duyên">'
    + '<div class="ai-chat-panel__header">'
    + '<span class="ai-chat-panel__avatar">' + BIRD_ICON_SM + '</span>'
    + '<span class="ai-chat-panel__title">'
    + '<span class="ai-chat-panel__name">Yến Duyên AI</span>'
    + '<span class="ai-chat-panel__status">Đang hoạt động</span>'
    + '</span>'
    + '<button class="ai-chat-panel__close" id="ai-chat-close" aria-label="Đóng chat">' + CLOSE_ICON_SM + '</button>'
    + '</div>'
    + '<div class="ai-chat-panel__messages">'
    + '<div class="ai-chat-msg ai-chat-msg--bot"><span class="ai-chat-msg__avatar">' + BIRD_ICON_XS + '</span><span class="ai-chat-msg__bubble">Xin chào! 👋 Em là trợ lý ảo của Yến Duyên. Em có thể giúp anh/chị tìm hiểu về sản phẩm, giá cả, cách bảo quản hay chính sách đổi trả — anh/chị cần hỗ trợ gì ạ?</span></div>'
    + '<div class="ai-chat-msg ai-chat-msg--user"><span class="ai-chat-msg__bubble">Yến sào bên mình có mấy loại vậy shop?</span></div>'
    + '<div class="ai-chat-msg ai-chat-msg--bot"><span class="ai-chat-msg__avatar">' + BIRD_ICON_XS + '</span><span class="ai-chat-msg__bubble"><span class="ai-chat-typing" aria-label="Đang soạn trả lời"><span></span><span></span><span></span></span></span></div>'
    + '</div>'
    + '<div class="ai-chat-panel__suggestions">'
    + '<button type="button" class="ai-chat-chip">Giá yến sào bao nhiêu?</button>'
    + '<button type="button" class="ai-chat-chip">Cách bảo quản yến</button>'
    + '<button type="button" class="ai-chat-chip">Chính sách đổi trả</button>'
    + '<button type="button" class="ai-chat-chip">Tư vấn quà tặng</button>'
    + '</div>'
    + '<div class="ai-chat-panel__input-row">'
    + '<input type="text" class="ai-chat-panel__input" placeholder="Nhập câu hỏi của bạn..." aria-label="Nhập tin nhắn">'
    + '<button type="button" class="ai-chat-panel__send" aria-label="Gửi tin nhắn">' + SEND_ICON + '</button>'
    + '</div>'
    + '</div>';

  function init() {
    var floatCta = document.querySelector('.float-cta');
    if (!floatCta || document.getElementById('ai-chat-toggle')) return; // không có cụm nút, hoặc đã chèn rồi thì bỏ qua

    floatCta.insertAdjacentHTML('beforeend', TOGGLE_HTML);
    floatCta.insertAdjacentHTML('afterend', PANEL_HTML);

    var toggleBtn = document.getElementById('ai-chat-toggle');
    var panel = document.getElementById('ai-chat-panel');
    var closeBtn = document.getElementById('ai-chat-close');
    if (!toggleBtn || !panel) return;

    function setOpen(open) {
      toggleBtn.classList.toggle('is-open', open);
      panel.classList.toggle('is-open', open);
      // Ẩn Gọi/Zalo/FB lúc mở chat — tránh chồng lấn với khung chat, đỡ rối mắt.
      floatCta.classList.toggle('is-chat-open', open);
      toggleBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
      toggleBtn.setAttribute('aria-label', open ? 'Đóng chat hỗ trợ' : 'Mở chat hỗ trợ');
    }
    toggleBtn.addEventListener('click', function () { setOpen(!panel.classList.contains('is-open')); });
    if (closeBtn) closeBtn.addEventListener('click', function () { setOpen(false); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
