// ============================================================
// NETLIFY FUNCTION — /api/chat (AI chat KHÁCH HÀNG).
// Rewrite từ /api/chat bởi netlify.toml. Đọc key Gemini từ ENV Netlify (qua
// relay-core), chỉ relay tới Gemini. Tool đọc dữ liệu vẫn chạy phía client.
// ============================================================
import { handleChat, CUSTOMER_PROMPT, CUSTOMER_TOOLS } from './_shared/relay-core.mjs';

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
    const result = await handleChat(body.contents, CUSTOMER_PROMPT, CUSTOMER_TOOLS, new Set());
    return new Response(JSON.stringify(result), { status: 200, headers: JSON_HEADERS });
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message || 'Lỗi server không rõ' }), { status: e.statusHint || 500, headers: JSON_HEADERS });
  }
};
