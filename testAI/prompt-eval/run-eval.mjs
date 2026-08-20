// ============================================================
// CHẠY TEST THẬT — gửi từng câu trong questions.mjs kèm system-prompt.txt
// tới Gemini (KHÔNG kèm tool, mỗi câu là 1 hội thoại độc lập — test riêng
// khả năng giữ vai/rào chắn của PROMPT, không phải test tool-calling).
// Ghi kết quả ra results.json + results.md để đọc lại.
// ============================================================
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { QUESTIONS } from './questions.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i === -1) continue;
    out[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return out;
}
const env = loadEnv(path.join(__dirname, '..', '.env'));
const GEMINI_API_KEY = env.GEMINI_API_KEY;
// Dùng model RIÊNG cho eval này (khác model của demo chính ở ../server.js) —
// gemini-3.6-flash đã cạn quota free-tier trong ngày (giới hạn 20 request/
// ngày, không phải /phút — đã xác minh bằng cách chờ 59s nhiều lần vẫn 429).
// gemini-3.1-flash-lite có bucket quota riêng, còn dùng được.
const GEMINI_MODEL = 'gemini-3.1-flash-lite';
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;
const SYSTEM_PROMPT = fs.readFileSync(path.join(__dirname, 'system-prompt.txt'), 'utf8');

if (!GEMINI_API_KEY) {
  console.error('Thiếu GEMINI_API_KEY trong testAI/.env');
  process.exit(1);
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// Free tier Gemini giới hạn ~20 request/phút — lỗi 429 kèm gợi ý "Please
// retry in Ns" trong message. Đọc đúng số giây đó ra để chờ rồi thử lại,
// thay vì bỏ cuộc ngay — tự thử tối đa 6 lần/câu.
function parseRetryDelaySec(msg) {
  const m = /retry in (\d+(?:\.\d+)?)s/i.exec(msg || '');
  return m ? Math.ceil(parseFloat(m[1])) : null;
}

async function callGeminiOnce(cauHoi) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 30000);
  try {
    const res = await fetch(`${GEMINI_URL}?key=${encodeURIComponent(GEMINI_API_KEY)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [{ role: 'user', parts: [{ text: cauHoi }] }],
      }),
      signal: controller.signal,
    });
    const json = await res.json();
    if (!res.ok) {
      const err = new Error(json?.error?.message || `HTTP ${res.status}`);
      err.httpStatus = res.status;
      throw err;
    }
    const parts = json?.candidates?.[0]?.content?.parts || [];
    const text = parts.filter(p => p.text).map(p => p.text).join('\n');
    const finishReason = json?.candidates?.[0]?.finishReason;
    return { text, finishReason };
  } finally {
    clearTimeout(timer);
  }
}

async function askOne(cauHoi) {
  const MAX_TRY = 6;
  for (let attempt = 1; attempt <= MAX_TRY; attempt++) {
    try {
      return await callGeminiOnce(cauHoi);
    } catch (e) {
      const isAbort = e.name === 'AbortError';
      const isRateLimit = e.httpStatus === 429;
      if ((isRateLimit || isAbort) && attempt < MAX_TRY) {
        const waitSec = (!isAbort && parseRetryDelaySec(e.message)) || (5 * attempt);
        process.stdout.write(`(429, chờ ${waitSec}s, thử lại ${attempt}/${MAX_TRY}) `);
        await sleep(waitSec * 1000 + 500); // +500ms đệm cho chắc
        continue;
      }
      return { loi: isAbort ? 'timeout' : e.message };
    }
  }
  return { loi: 'Hết số lần thử lại' };
}

async function main() {
  const results = [];
  for (const q of QUESTIONS) {
    process.stdout.write(`[${q.id}/30] (${q.nhom}) đang hỏi... `);
    const r = await askOne(q.cau);
    results.push({ ...q, tra_loi: r.text || null, loi: r.loi || null, finishReason: r.finishReason || null });
    console.log(r.loi ? `LỖI: ${r.loi}` : 'OK');
    await sleep(3500); // free tier ~20 request/phút — chừa khoảng cách chủ động
  }
  fs.writeFileSync(path.join(__dirname, 'results.json'), JSON.stringify(results, null, 2), 'utf8');

  const md = ['# Kết quả test prompt tư vấn viên — ' + new Date().toISOString(), ''];
  for (const r of results) {
    md.push(`## [${r.id}] (${r.nhom}) ${r.cau}`);
    md.push('');
    md.push('**Tiêu chí:** ' + r.tieu_chi);
    md.push('');
    md.push('**Trả lời:**');
    md.push('');
    md.push(r.loi ? `_LỖI: ${r.loi}_` : (r.tra_loi || '_(rỗng)_'));
    md.push('');
    md.push('---');
    md.push('');
  }
  fs.writeFileSync(path.join(__dirname, 'results.md'), md.join('\n'), 'utf8');
  console.log('\nĐã ghi results.json + results.md');
}

main();
