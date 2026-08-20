// ============================================================
//  SUPABASE CLIENT + AUTH HELPERS — Yến Sào Yến Duyên
//  Script thường (KHÔNG phải module). Nạp sau CDN @supabase/supabase-js@2.
//  Mọi hàm gắn vào window để các <script> inline dùng được.
// ============================================================

var SUPABASE_URL = 'https://lhbnkolpqziybodyrins.supabase.co';
var SUPABASE_ANON_KEY = 'sb_publishable_M6VyIk3-rCvhpLi40W2quA_bfkqhyuU';

// Domain ảo dùng cho tài khoản đăng nhập bằng SỐ ĐIỆN THOẠI (không gửi SMS).
// Khách chỉ thấy mình nhập SĐT + mật khẩu; bên dưới ta quy đổi thành email nội bộ.
var PHONE_EMAIL_DOMAIN = 'phone.yenduyen.local';

// window._supabase được khởi tạo 1 lần duy nhất, dùng chung toàn site
function getSupabase() {
  if (!window._supabase) {
    window._supabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }
  return window._supabase;
}

// ─── PHONE ⇄ EMAIL NỘI BỘ ────────────────────────────────────
// Chuẩn hoá SĐT VN: bỏ khoảng trắng/ký tự thừa, đổi +84 → 0
function normalizePhone(raw) {
  if (!raw) return '';
  var p = ('' + raw).replace(/[^0-9+]/g, '');
  if (p.indexOf('+84') === 0) p = '0' + p.slice(3);
  else if (p.indexOf('84') === 0 && p.length === 11) p = '0' + p.slice(2);
  return p;
}
function isValidPhone(raw) {
  return /^0[3-9][0-9]{8}$/.test(normalizePhone(raw));
}
// SĐT → email nội bộ (vd: 0986012754 → 0986012754@phone.yenduyen.local)
function phoneToEmail(raw) {
  return normalizePhone(raw) + '@' + PHONE_EMAIL_DOMAIN;
}
// Kiểm tra 1 email có phải email nội bộ của tài khoản SĐT không
function isPhoneEmail(email) {
  return !!email && email.indexOf('@' + PHONE_EMAIL_DOMAIN) !== -1;
}

// ─── SESSION / USER ──────────────────────────────────────────
// Trả về Promise<user|null>
function getCurrentUser() {
  return getSupabase().auth.getUser().then(function (res) {
    return (res && res.data && res.data.user) ? res.data.user : null;
  }).catch(function () { return null; });
}
// Trả về Promise<session|null>
function getCurrentSession() {
  return getSupabase().auth.getSession().then(function (res) {
    return (res && res.data && res.data.session) ? res.data.session : null;
  }).catch(function () { return null; });
}
// Lấy hồ sơ (bảng profiles) của user hiện tại → Promise<profile|null>
function getMyProfile() {
  return getCurrentUser().then(function (user) {
    if (!user) return null;
    return getSupabase().from('profiles').select('*').eq('id', user.id).single()
      .then(function (res) { return res.data || null; });
  });
}
// Đăng xuất rồi về trang chủ (hoặc URL truyền vào)
function signOutAndRedirect(redirectTo) {
  return getSupabase().auth.signOut().then(function () {
    window.location.href = redirectTo || 'index.html';
  });
}
// Bắt buộc đăng nhập: nếu chưa → chuyển sang trang đăng nhập, kèm redirect quay lại trang hiện tại.
// Trả về Promise<user> (nếu đã đăng nhập) — nếu chưa thì điều hướng luôn, Promise không resolve.
function requireAuth(loginPath) {
  return getCurrentUser().then(function (user) {
    if (user) return user;
    var here = window.location.pathname.split('/').pop() + window.location.search;
    var prefix = (loginPath || 'dang-nhap.html');
    window.location.href = prefix + '?redirect=' + encodeURIComponent(here);
    return new Promise(function () {}); // không resolve, vì đang chuyển trang
  });
}

// ─── AVATAR HELPERS ─────────────────────────────────────────
// Bảng màu gradient hợp tông website (nâu → nâu sáng / gold / đỏ đô)
var AVATAR_GRADIENTS = [
  'linear-gradient(135deg,#3E2723,#8D6E63)',
  'linear-gradient(135deg,#5D4037,#A1887F)',
  'linear-gradient(135deg,#4E342E,#D4AF37)',
  'linear-gradient(135deg,#3E2723,#8B0000)',
  'linear-gradient(135deg,#6D4C41,#C9A227)',
  'linear-gradient(135deg,#5D4037,#3E2723)'
];
// Chọn gradient ổn định theo seed (id user) để mỗi người 1 màu cố định
function avatarGradientFor(seed) {
  var s = ('' + (seed || 'x'));
  var sum = 0;
  for (var i = 0; i < s.length; i++) sum += s.charCodeAt(i);
  return AVATAR_GRADIENTS[sum % AVATAR_GRADIENTS.length];
}
// Lấy chữ cái đầu của tên (hoặc 'Y' mặc định)
function avatarInitial(name) {
  var n = (name || '').trim();
  if (!n) return 'Y';
  return n.charAt(0).toUpperCase();
}

// ─── DỊCH LỖI SUPABASE SANG TIẾNG VIỆT ──────────────────────
function mapAuthError(msg) {
  if (!msg) return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
  if (msg.indexOf('Invalid login') !== -1) return 'Tài khoản hoặc mật khẩu không đúng.';
  if (msg.indexOf('Email not confirmed') !== -1) return 'Tài khoản chưa được xác nhận.';
  if (msg.indexOf('User already registered') !== -1) return 'Tài khoản này đã tồn tại. Vui lòng đăng nhập.';
  if (msg.indexOf('already registered') !== -1) return 'Tài khoản này đã tồn tại. Vui lòng đăng nhập.';
  if (msg.indexOf('Password should be') !== -1) return 'Mật khẩu phải có ít nhất 6 ký tự.';
  if (msg.indexOf('rate limit') !== -1) return 'Quá nhiều yêu cầu. Vui lòng thử lại sau vài phút.';
  if (msg.indexOf('Unable to validate email') !== -1) return 'Định dạng không hợp lệ.';
  return msg;
}
