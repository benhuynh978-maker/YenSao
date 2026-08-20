// ============================================================
// SUPABASE CLIENT (đọc công khai) — testAI. Cùng project Supabase với site
// chính, dùng anon key công khai giống hệt js/supabase-client.js ở repo gốc.
// Không có auth/session ở đây — testAI chỉ demo tool đọc dữ liệu công khai.
// ============================================================
var SUPABASE_URL = 'https://lhbnkolpqziybodyrins.supabase.co';
var SUPABASE_ANON_KEY = 'sb_publishable_M6VyIk3-rCvhpLi40W2quA_bfkqhyuU';

function getSupabase() {
  if (!window._supabase) {
    window._supabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }
  return window._supabase;
}
