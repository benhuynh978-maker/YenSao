// Thay Hotline/Zalo/Facebook viết cứng trong HTML bằng dữ liệu thật từ
// bảng public.site_settings khi admin đã cập nhật ở admin/cai-dat.html.
// Nếu tải lỗi/chưa có dữ liệu thì GIỮ NGUYÊN số/link viết cứng sẵn trong
// HTML (fail-open, không làm hỏng trang).
(function () {
  var OLD_PHONE_DISPLAY = '0986.012.754';
  var OLD_TEL_HREF = 'tel:+840986012754';
  var OLD_ZALO_PREFIX = 'https://zalo.me/0986012754';
  var OLD_FB_URL = 'https://facebook.com/yensaoyenduyen';
  // Nút nổi "Facebook" (float-btn--fb) trước đây trỏ tới link Messenger
  // (m.me/...) — theo yêu cầu, giờ trỏ thẳng tới Fanpage thật, giống hệt
  // icon Facebook ở footer, không mở Messenger nữa.
  var OLD_MESSENGER_URL = 'https://m.me/yensaoyenduyen';
  var OLD_EMAIL = 'lienhe@yensaoyenduyen.vn';
  var OLD_MAILTO_HREF = 'mailto:' + OLD_EMAIL;
  var OLD_ADDRESS_FULL = '503 ĐH507, Phước Thành, Hồ Chí Minh, Vietnam';
  var OLD_ADDRESS_SHORT = OLD_ADDRESS_FULL;
  var SETTINGS_TIMEOUT_MS = 4000;

  function digitsOnly(s) { return (s || '').replace(/\D/g, ''); }
  function formatVNPhone(digits) {
    if (digits.length !== 10) return digits;
    return digits.slice(0, 4) + '.' + digits.slice(4, 7) + '.' + digits.slice(7);
  }
  function telHrefFromDigits(digits) { return 'tel:+84' + digits.replace(/^0/, ''); }

  function replaceTextEverywhere(oldStr, newStr) {
    if (!oldStr || !newStr || oldStr === newStr) return;
    var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
    var nodes = [];
    var node;
    while ((node = walker.nextNode())) nodes.push(node);
    nodes.forEach(function (n) {
      if (n.nodeValue.indexOf(oldStr) !== -1) {
        n.nodeValue = n.nodeValue.split(oldStr).join(newStr);
      }
    });
  }

  // ─── Tải dữ liệu thật — CHỈ tải 1 lần (nhiều nơi cùng dùng chung 1 promise
  // này), có giới hạn thời gian chờ để không treo vô hạn nếu mạng lỗi.
  var settingsPromise = null;
  function loadSettings() {
    if (settingsPromise) return settingsPromise;
    if (typeof getSupabase !== 'function') { settingsPromise = Promise.resolve(null); return settingsPromise; }
    var fetchPromise = getSupabase().from('site_settings').select('phone,zalo_phone,facebook_url,email,address').eq('id', 1).single()
      .then(function (res) { return (res && res.data) ? res.data : null; })
      .catch(function () { return null; });
    var timeoutPromise = new Promise(function (resolve) {
      setTimeout(function () { resolve(null); }, SETTINGS_TIMEOUT_MS);
    });
    settingsPromise = Promise.race([fetchPromise, timeoutPromise]);
    return settingsPromise;
  }

  function zaloUrlFromSettings(s) {
    if (!s || !s.zalo_phone) return null;
    var zDigits = digitsOnly(s.zalo_phone);
    return zDigits.length === 10 ? 'https://zalo.me/' + zDigits : null;
  }

  // ─── Cập nhật SẴN href/chữ hiển thị ngay khi tải xong (để hover/"Sao chép
  // liên kết" ra đúng link mà không cần đợi bấm) — đây là cập nhật "sớm nếu
  // kịp", KHÔNG phải chỗ duy nhất đảm bảo đúng (xem guardLinkClicks bên dưới
  // mới là chỗ đảm bảo chắc chắn, kể cả khi bấm quá nhanh).
  function applyEagerUpdates(s) {
    if (!s) return;
    if (s.phone) {
      var digits = digitsOnly(s.phone);
      if (digits.length === 10) {
        var newDisplay = formatVNPhone(digits);
        var newTel = telHrefFromDigits(digits);
        document.querySelectorAll('a[href="' + OLD_TEL_HREF + '"]').forEach(function (a) {
          a.setAttribute('href', newTel);
        });
        replaceTextEverywhere(OLD_PHONE_DISPLAY, newDisplay);
      }
    }
    var zaloUrl = zaloUrlFromSettings(s);
    if (zaloUrl) {
      document.querySelectorAll('a[href^="' + OLD_ZALO_PREFIX + '"]').forEach(function (a) {
        a.setAttribute('href', zaloUrl + a.getAttribute('href').slice(OLD_ZALO_PREFIX.length));
      });
    }
    if (s.facebook_url) {
      document.querySelectorAll('a[href="' + OLD_FB_URL + '"], a[href="' + OLD_MESSENGER_URL + '"]').forEach(function (a) {
        a.setAttribute('href', s.facebook_url);
      });
    }
    if (s.email) {
      document.querySelectorAll('a[href="' + OLD_MAILTO_HREF + '"]').forEach(function (a) {
        a.setAttribute('href', 'mailto:' + s.email);
      });
      replaceTextEverywhere(OLD_EMAIL, s.email);
    }
    if (s.address) {
      replaceTextEverywhere(OLD_ADDRESS_FULL, s.address);
      replaceTextEverywhere(OLD_ADDRESS_SHORT, s.address);
    }
  }

  // ─── Chặn CLICK trên các link Zalo/Facebook — đợi chắc chắn đã có dữ liệu
  // thật (hoặc hết giờ chờ) rồi mới thật sự điều hướng. Đây là chỗ đảm bảo
  // KHÔNG BAO GIỜ mở nhầm link cũ, kể cả khi khách bấm ngay lúc trang vừa tải
  // xong (trước khi kịp tải dữ liệu thật từ Supabase).
  function guardLinkClicks(selector, computeUrl) {
    document.querySelectorAll(selector).forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var fallbackHref = a.getAttribute('href');
        loadSettings().then(function (s) {
          var url = computeUrl(s) || fallbackHref;
          window.open(url, '_blank', 'noopener');
        });
      });
    });
  }

  // ─── Số điện thoại không "truy cập" được như 1 trang web — bấm vào trên
  // máy tính (không phải điện thoại) mặc định không làm gì cả. Trên điện
  // thoại thì mở app gọi điện (đợi dữ liệu thật trước, tránh gọi nhầm số cũ
  // nếu bấm quá nhanh). Trên máy tính, sao chép số vào clipboard.
  function isMobileLike() {
    return /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || '');
  }
  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;opacity:0';
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand('copy'); } catch (e) {}
    ta.remove();
    return Promise.resolve();
  }
  function showSimpleToast(message) {
    var el = document.createElement('div');
    el.textContent = message;
    el.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);' +
      'background:#1a1a2e;color:#fff;padding:12px 20px;border-radius:8px;font-size:14px;' +
      'z-index:9999;box-shadow:0 4px 16px rgba(0,0,0,.2);opacity:0;transition:opacity .25s;' +
      'max-width:90vw;text-align:center;';
    document.body.appendChild(el);
    requestAnimationFrame(function () { el.style.opacity = '1'; });
    setTimeout(function () {
      el.style.opacity = '0';
      setTimeout(function () { el.remove(); }, 300);
    }, 2400);
  }
  function enablePhoneClickGuard() {
    document.querySelectorAll('a[href^="tel:"]').forEach(function (a) {
      var fallbackHref = a.getAttribute('href');
      a.addEventListener('click', function (e) {
        e.preventDefault();
        loadSettings().then(function (s) {
          var digits = s && s.phone ? digitsOnly(s.phone) : '';
          var tel = digits.length === 10 ? telHrefFromDigits(digits) : fallbackHref;
          var display = digits.length === 10 ? formatVNPhone(digits) : telHrefToDisplay(fallbackHref);
          if (isMobileLike()) {
            window.location.href = tel;
          } else {
            copyText(display).then(function () {
              showSimpleToast('Đã sao chép số điện thoại ' + display + ' — dán vào Zalo/tin nhắn để liên hệ nhé');
            });
          }
        });
      });
    });
  }
  function telHrefToDisplay(href) {
    var digits = (href || '').replace(/\D/g, '');
    if (digits.length === 11 && digits.indexOf('84') === 0) digits = '0' + digits.slice(2);
    if (digits.length !== 10) return (href || '').replace('tel:+84', '0');
    return digits.slice(0, 4) + '.' + digits.slice(4, 7) + '.' + digits.slice(7);
  }

  function run() {
    enablePhoneClickGuard();
    guardLinkClicks('a[href="' + OLD_FB_URL + '"], a[href="' + OLD_MESSENGER_URL + '"]', function (s) { return s && s.facebook_url; });
    guardLinkClicks('a[href^="' + OLD_ZALO_PREFIX + '"]', zaloUrlFromSettings);
    guardLinkClicks('a[href="' + OLD_MAILTO_HREF + '"]', function (s) { return s && s.email && 'mailto:' + s.email; });
    loadSettings().then(applyEagerUpdates);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
