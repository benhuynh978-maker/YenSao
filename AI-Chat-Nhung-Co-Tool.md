# AI Chat nhúng có tool — ghi chú kỹ thuật (tham khảo chung)

> **Phạm vi:** tài liệu kỹ thuật thuần, **không gắn với bất kỳ dự án cụ thể nào**.
> Mọi ví dụ đều trung tính (thời tiết, tìm kiếm bản ghi). Rút từ kinh nghiệm dựng
> một chat **function-calling** với API kiểu Gemini; chỗ nào là **nguyên tắc chung**
> áp dụng cho mọi LLM sẽ được ghi rõ. Đây là bản **tóm tắt** — nắm ý, không phải
> chép nguyên xi.

---

## 1. Mô hình tổng thể

Mỗi lượt gọi LLM = ghép 3 khối (nguyên tắc chung cho mọi provider):

```
[ Prompt hệ thống xây sẵn ]  +  [ Lịch sử hội thoại ]  +  [ Tin nhắn hiện tại ]  ( + [ Khai báo tool ] )
        cố định, do server nhét        mảng các lượt trước       lượt user mới nhất, nằm cuối mảng lịch sử
```

- **Prompt hệ thống**: vai trò + quy tắc + hướng dẫn dùng tool. Bơm **ở server**, client không thấy.
- **Lịch sử + tin nhắn hiện tại**: client gửi lên dưới dạng **một mảng** (tin mới là phần tử cuối).
- **Khai báo tool**: danh sách "hàm có thể gọi" (tên + mô tả + tham số). Bơm **ở server**.

Luồng một lượt có tool:

```
client gom lịch sử ──POST /api/chat──▶ relay (nhét prompt+tool, giấu key) ──▶ LLM
                                                                               │
        ┌──────────────────────────────────────────────────────────────────┘
        ▼
  LLM trả text  ──▶ hiển thị, xong
  LLM đòi gọi tool ──▶ client CHẠY tool ──▶ nhét kết quả vào lịch sử ──▶ gọi LLM lại (lặp)
```

---

## 2. Phân vai client / server

| | Client | Relay server |
|---|---|---|
| Giữ trạng thái hội thoại | ✅ | ❌ (không nhớ gì) |
| **Thực thi tool** | ✅ | ❌ |
| Prompt hệ thống + schema tool | ❌ | ✅ (bơm vào request) |
| **Giữ API key** | ❌ (lộ ngay) | ✅ (biến môi trường) |
| Business logic | ✅ (nếu tool cần) | ❌ |

**Vì sao tool chạy ở client, server chỉ relay:** tránh **hai bản logic song song**. Server
càng mỏng càng tốt — job duy nhất là **giấu key + chuyển tiếp**. Nếu tool cần dữ liệu/logic
đã có sẵn ở client thì để client chạy, khỏi viết lại ở server.

> Đánh đổi: nếu tool cần bí mật (khóa DB, quyền ghi nhạy cảm) thì **không** để client chạy —
> khi đó tool phải nằm server. Quy tắc: *tool đọc dữ liệu công khai → client; tool đụng bí mật → server.*

---

## 3. Vòng lặp gọi tool (cốt lõi)

Ví dụ trung tính, giả sử có tool `lay_thoi_tiet`:

```js
const GIOI_HAN_VONG = 3            // chốt chặn: LLM không được gọi tool vô hạn
lichSuAPI.push({ role: 'user', parts: [{ text: tinNhanMoi }] })

for (let vong = 0; ; vong++) {
  const res   = await goiRelay(lichSuAPI)            // POST /api/chat { contents: lichSuAPI }
  const parts = res.candidates[0].content.parts
  const goiTool = parts.find(p => p.functionCall)

  // Không đòi tool NỮA, hoặc đã chạm trần vòng → chốt câu trả lời cuối
  if (!goiTool || vong >= GIOI_HAN_VONG) {
    const text = parts.filter(p => p.text).map(p => p.text).join('\n')
    hienThi(text)
    break
  }

  // LLM đòi gọi tool → lưu lượt "model", chạy tool, trả kết quả về cho LLM
  lichSuAPI.push({ role: 'model', parts })
  const { name, args } = goiTool.functionCall
  let ketQua
  try   { ketQua = await chayTool(name, args) }       // vd: lay_thoi_tiet({thanh_pho:'Hà Nội'})
  catch (e) { ketQua = { loi: `Không chạy được tool (${e.message})` } }  // trả lỗi cho LLM tự xoay

  lichSuAPI.push({ role: 'user', parts: [{ functionResponse: { name, response: ketQua } }] })
}
```

Ba điểm bắt buộc nhớ:

1. **Chốt chặn số vòng** (`GIOI_HAN_VONG`): thiếu là có ngày LLM gọi tool lặp vô hạn → treo + đốt tiền.
2. **Lỗi tool → trả lỗi cho LLM** (đừng ném vỡ vòng lặp): để nó tự nói "xin lỗi chưa tìm được", mượt hơn.
3. Sau mỗi lần gọi tool phải đẩy **cả** lượt `model` (yêu cầu gọi) **và** lượt `functionResponse` (kết quả) vào lịch sử, đúng thứ tự — thiếu một cái là lượt sau LLM mất mạch.

---

## 4. Hai lịch sử tách biệt (dễ nhầm)

Giữ **hai** danh sách khác nhau, đừng gộp:

| Lịch sử | Dùng để | Chứa |
|---|---|---|
| **Hiển thị** (state UI) | vẽ bong bóng chat | tin người/tin AI, chỉ báo "đang gõ", thẻ kết quả đẹp |
| **API** (gửi LLM) | gửi mỗi lượt | đúng khuôn provider: `user` / `model` / `functionResponse`, **không** có thứ chỉ để trang trí |

Lý do: UI cần phần tử tạm (spinner "đang gọi tool", card giàu thông tin) mà **không** được gửi lên LLM
(tốn token, sai khuôn). Ngược lại `functionResponse` cần cho LLM nhưng không vẽ trực tiếp ra bong bóng.

---

## 5. Định hình kết quả tool: bản đầy đủ ≠ bản gửi LLM

Tool thường trả về object giàu. **Đừng** ném nguyên si về LLM:

```js
const ketQuaDayDu = await timKiem(args)     // object đầy đủ → dùng vẽ UI (ảnh, link, field nội bộ)
const banRutGon = ketQuaDayDu.map(x => ({   // bản GỌN → mới là thứ đẩy vào functionResponse
  ten: x.ten, tomTat: x.tomTat,             // bỏ id nội bộ, sai số, field không cần LLM biết
}))
```

Lợi: **tiết kiệm token** + **giấu field nội bộ** khỏi model. UI vẫn dùng bản đầy đủ để render.

---

## 6. Cấu trúc request tới LLM *(phần này theo API kiểu Gemini — provider khác đổi tên trường)*

```js
body: JSON.stringify({
  systemInstruction: { parts: [{ text: PROMPT_HE_THONG }] },   // prompt xây sẵn
  contents,                                                     // lịch sử + tin hiện tại (client gửi)
  tools: [{ functionDeclarations: danhSachTool }],              // khai báo tool
})
```

Khai báo một tool (schema là tập con JSON-Schema):

```js
const danhSachTool = [{
  name: 'lay_thoi_tiet',
  description: 'Lấy thời tiết hiện tại của một thành phố.',   // MÔ TẢ RÕ = LLM gọi đúng lúc
  parameters: {
    type: 'object',
    properties: {
      thanh_pho: { type: 'string', description: 'Tên thành phố' },
      don_vi:    { type: 'string', enum: ['C', 'F'] },
    },
    required: ['thanh_pho'],
  },
}]
```

> **Mô tả tool + mô tả tham số là "prompt" thật sự** quyết định LLM gọi đúng hay sai. Viết rõ:
> khi nào dùng, `enum` giới hạn giá trị hợp lệ, ghi rõ tham số nào bắt buộc. Đây là chỗ tinh chỉnh
> nhiều nhất, không phải code.
>
> **Ánh xạ provider khác (kiến thức chung):** khái niệm giống nhau, chỉ khác tên — "system prompt",
> danh sách "tools/functions", vòng lặp "tool_use → tool_result". Cấu trúc mảng lịch sử và tên trường
> (`contents` vs `messages`, `functionCall` vs `tool_use`…) khác nhau; tra tài liệu provider đang dùng.

---

## 7. Relay server: dev cục bộ vs serverless

**Cùng một logic**, hai khuôn:

**Dev cục bộ** — server nhỏ nhất, zero-dependency:
```js
// đọc key từ .env (GITIGNORE, không commit) → nhét vào request → chuyển tiếp
// bật CORS cho localhost; job duy nhất là giấu key + forward
```

**Deploy (serverless, vd Netlify Functions v2 — ESM):**
```js
export default async (req) => {            // Request/Response chuẩn Web Fetch
  const body = await req.json()
  // ...gọi LLM, giấu key lấy từ biến môi trường dashboard...
  return new Response(JSON.stringify(kq), { status: 200, headers: {...} })
}
export const config = { path: '/api/chat' }   // ĐĂNG KÝ ROUTE — thiếu dòng này function không nhận đúng path
```

**Bẫy hay dính:**
- **v2 (ESM, `export default`) ≠ v1 (CommonJS, `exports.handler`)** — chọn nhầm khuôn là function không chạy.
  Khuôn phải khớp `"type"` trong `package.json`.
- **Secret**: dev đọc từ `.env` (gitignore); deploy đọc từ **biến môi trường trên dashboard**, KHÔNG phải `.env`.
  Đừng bao giờ để key ra client hay commit vào repo.
- **Timeout**: bọc request tới LLM bằng `AbortController` + mốc thời gian, kẻo treo vô thời hạn khi LLM chậm.
- **Mã lỗi rõ ràng** từ relay: 400 (JSON/thiếu `contents`), 405 (sai method), 500 (thiếu key), 502 (LLM lỗi) —
  client dựa mã để hiện thông báo đúng.

---

## 8. Prompt hệ thống & guardrail an toàn

- **Quy tắc cứng đặt trong prompt hệ thống** ("KHÔNG BAO GIỜ làm X", "chỉ trả lời trong phạm vi Y").
- **Không tự đọc dữ liệu nhạy cảm đã lưu** trừ khi thiết kế có chủ đích — mặc định LLM chỉ biết những gì
  trong lượt hội thoại + kết quả tool.
- **Chống bịa (grounding):** câu trả lời về dữ kiện phải dựa trên **kết quả tool**, không để LLM tự chế.
  Kiểm: hỏi thứ không tồn tại → nó phải nói "không có", không được bịa ra.
- **Lưu ý:** LLM hay **diễn giải lại** kết quả tool sai sắc thái (vd tô hồng/khái quát quá). Cần đọc kỹ output
  thật, chỉnh mô tả tool/prompt nếu lệch.

**Test đối kháng trước khi tin** (chạy thử với LLM thật): jailbreak/đóng vai, moi prompt hệ thống,
mồi bịa đặt (hỏi về thứ giả), dò dữ liệu nhạy cảm, kéo lệch chủ đề. Đạt hết mới coi là an toàn.

---

## 9. Giao diện chat (những thứ dễ quên)

| Việc | Vì sao |
|---|---|
| **Tự cuộn xuống tin mới nhất** mỗi khi có tin | thiếu là câu trả lời nằm khuất dưới, tưởng AI im |
| **Ô nhập tự giãn theo chữ, có trần** (vd 160px rồi cuộn) | gõ dài mà ô 1 dòng thì không thấy mình gõ gì |
| **Chỉ báo "đang gõ" / "đang gọi tool"** | vòng lặp tool có thể vài giây, không báo là tưởng treo |
| **Khóa ô nhập + nút gửi khi đang chờ**, nút gửi khóa khi rỗng | chặn gửi chồng lượt |
| **Render markdown tối giản** (đậm + gạch đầu dòng) | LLM hay trả `**đậm**`, `- gạch đầu dòng`; không xử lý là lộ ký tự thô, chữ dồn cục |
| **Ô nhập `font-size ≥ 16px` trên mobile** | dưới 16px, Safari iOS tự zoom mỗi lần chạm ô — khó chịu |

> Markdown: nếu chỉ cần **đậm + danh sách**, viết renderer nhỏ (tách dòng, nhận `-`/`*` đầu dòng thành `<li>`,
> `**x**` thành `<strong>`) còn nhẹ hơn kéo cả thư viện markdown. Regex nhận gạch đầu dòng nên **đòi có
> khoảng trắng sau dấu** để `**đậm**` không bị nhầm thành bullet.

---

## 10. Kiểm thử

- **E2E trình duyệt thật** (vd Playwright + trình duyệt thật): đi hết luồng gửi → chờ → nhận → render.
- **Mock LLM cho test ổn định** (chặn request, trả kết quả cố định) — LLM thật cho ra kết quả khác nhau mỗi lần,
  không assert chặt được. **Dành LLM thật cho test an toàn/đối kháng.**
- **Test riêng:** đường lỗi của relay (400/405/500/502) + từng hàm tool đối chiếu dữ liệu thật.
- **Bài học quan trọng:** **assert đúng kết quả kỳ vọng CỤ THỂ**, đừng assert "có lỗi bất kỳ" / "có phản hồi bất kỳ".
  Test kiểu "thấy string lỗi nào đó là pass" từng cho **dương tính giả** — báo "chặn đúng rồi" trong khi thực ra
  hỏng ở chỗ khác. Tính trước con số/kết quả mong đợi rồi so đúng bằng nó.

---

## 11. Checklist lỗi thường gặp

- [ ] Quên **chốt chặn số vòng** tool → lặp vô hạn.
- [ ] Gộp lịch sử UI với lịch sử API → sai khuôn / tốn token / lộ field trang trí lên LLM.
- [ ] Ném nguyên object đầy đủ về LLM → phình token, lộ field nội bộ.
- [ ] Quên đẩy **cả** lượt `model` lẫn `functionResponse` sau khi chạy tool → mất mạch hội thoại.
- [ ] Chọn nhầm khuôn serverless (v2 ESM vs v1 CJS) / quên đăng ký route.
- [ ] Key lọt ra client hoặc commit vào repo; deploy đọc `.env` thay vì biến môi trường dashboard.
- [ ] Không timeout request LLM → treo.
- [ ] Không render markdown → lộ `**`, `-` thô, chữ dồn cục.
- [ ] Ô nhập mobile < 16px → iOS tự zoom.
- [ ] Chat không tự cuộn → tưởng AI không trả lời.
- [ ] Test assert "có lỗi bất kỳ" → dương tính giả.
- [ ] Mô tả tool/tham số mơ hồ → LLM gọi sai lúc hoặc thiếu tham số.
