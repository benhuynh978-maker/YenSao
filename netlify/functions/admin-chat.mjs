// ============================================================
// NETLIFY FUNCTION — /api/admin-chat (AI chat ADMIN, phân tích kinh doanh).
// Giống chat.mjs nhưng dùng prompt + tool ADMIN. 4 tool báo cáo vẫn chạy phía
// client dưới phiên admin thật (RLS + is_admin() tự chặn — đã pentest); function
// chỉ relay tới Gemini, không giữ dữ liệu nhạy cảm.
// ============================================================
import { handleChat, ADMIN_PROMPT, ADMIN_TOOLS } from './_shared/relay-core.mjs';

const JSON_HEADERS = { 'Content-Type': 'application/json; charset=utf-8' };

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204 });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Chỉ nhận POST' }), { status: 405, headers: JSON_HEADERS });
  }
  let body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'JSON không hợp lệ' }), { status: 400, headers: JSON_HEADERS });
  }
  if (!Array.isArray(body.contents) || !body.contents.length) {
    return new Response(JSON.stringify({ error: 'Thiếu trường "contents" (mảng lịch sử hội thoại)' }), { status: 400, headers: JSON_HEADERS });
  }
  try {
    const result = await handleChat(body.contents, ADMIN_PROMPT, ADMIN_TOOLS, new Set());
    return new Response(JSON.stringify(result), { status: 200, headers: JSON_HEADERS });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || 'Lỗi server không rõ' }), { status: e.statusHint || 500, headers: JSON_HEADERS });
  }
};
