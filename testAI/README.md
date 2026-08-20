# testAI — Demo AI Chat có Tool (function-calling)

Dự án demo ĐỘC LẬP, dựng theo kiến trúc mô tả trong `../AI-Chat-Nhung-Co-Tool.md`.
Không đụng tới bất kỳ file nào của website chính. **Nhóm A**: 3 tool đọc dữ
liệu CÔNG KHAI, lấy THẬT từ Supabase của site chính (không giả lập nữa) —
không cần đăng nhập/xác thực danh tính. Nhóm B (đụng dữ liệu cá nhân — tra
đơn hàng, ưu đãi theo SĐT) đã quyết định tạm hoãn, xem mục cuối file.

## Chạy demo

```bash
cd testAI
node server.js
# hoặc: npm start
```

Mở `http://localhost:8792` — bấm bong bóng chat góc phải dưới.

Cần Node.js ≥ 18 (dùng `fetch` built-in). Đã test với Node v24.

## Cấu trúc

```
testAI/
  server.js                 # relay server (zero-dependency, http + fetch built-in)
  .env                      # GEMINI_API_KEY thật (đã .gitignore, KHÔNG commit)
  .env.example               # mẫu để tự điền key khác
  public/
    index.html              # trang khách hàng demo, gắn sẵn widget chat
    css/style.css            # giao diện bong bóng chat + khung chat (tự viết)
    js/chat-widget.js        # logic UI + vòng lặp tool-calling phía client
    js/tools.js               # 3 tool CHẠY Ở CLIENT — Supabase THẬT (chỉ đọc)
    js/supabase-client.js     # khởi tạo Supabase client (anon key công khai)
  prompt-eval/                # bộ test 30 câu (cơ bản → công kích) cho prompt
                               # nhân viên tư vấn, độc lập với phần tool ở trên
```

## 3 tool (Nhóm A) — mỗi bảng Supabase = 1 tool khai báo

Quyết định thiết kế: gộp theo BẢNG dữ liệu (không phải theo "loại câu hỏi")
để giảm số tool phải khai báo mỗi lượt gọi (đỡ tốn token) — mỗi tool có tham
số `hanh_dong`/logic nội bộ để xử lý nhiều kiểu truy vấn khác nhau trên cùng
1 bảng, coi như "tool con".

| Tool | Bảng | Tool con |
|---|---|---|
| `san_pham` | `products` | `tim_kiem` (từ khoá/giá tối đa), `chi_tiet` (theo id) |
| `flash_sale` | `flash_sales` + `flash_sale_items` | 1 hành động — đợt đang/sắp diễn ra kèm SP giảm giá |
| `thong_tin_cua_hang` | `site_settings` | 1 hành động — địa chỉ/hotline/Zalo/Facebook/email |

**Đã bỏ khỏi phạm vi (quyết định có chủ đích, không phải thiếu sót):**
- Tool đánh giá (`reviews`) — bỏ hẳn, tránh phức tạp thêm.
- Tool `voucher` — **không xây được dù đã lên kế hoạch ban đầu**: kiểm tra
  thật phát hiện bảng `vouchers` đã bị khoá quyền đọc cho `anon` (vá lỗ hổng
  thật trước đây, xem `sql/fix-vouchers-read-lockdown.sql` ở repo chính — lỗi
  P1-1: từng lộ toàn bộ mã voucher cho người lạ). RPC thay thế `check_voucher`
  cũng chỉ cấp quyền cho `authenticated`, `anon` gọi bị từ chối (đã test trực
  tiếp: `permission denied for function check_voucher`). KHÔNG mở lại quyền
  này chỉ để phục vụ tool — system prompt đã dặn AI mời khách liên hệ
  hotline/Zalo nếu hỏi voucher, không tự bịa mã.
- Tra đơn hàng, ưu đãi thành viên theo SĐT (Nhóm B) — cần xác thực danh tính
  chặt, rủi ro bị lợi dụng dò thông tin khách khác — để bàn riêng sau.
- Phí vận chuyển + chính sách đổi trả/bảo quản — **không vào prompt, không
  thành tool** (2 mảng này không có trong Supabase). Thay bằng 2 nút gợi ý
  "Phí vận chuyển"/"Chính sách đổi trả" trong khung chat — bấm vào hiện
  thẳng nội dung CỐ ĐỊNH viết sẵn (`CANNED_BOXES` trong `chat-widget.js`),
  KHÔNG qua AI, KHÔNG có rủi ro bịa. Nếu khách gõ tay hỏi 2 việc này, system
  prompt dặn AI mời khách bấm đúng nút hoặc liên hệ hotline.

## Kiến trúc — bám theo tài liệu

- **Prompt hệ thống + khai báo tool**: nằm hẳn trong `server.js`, client
  không bao giờ thấy (mục 2 tài liệu).
- **API key**: chỉ đọc từ `.env` phía server, không lộ ra response nào gửi
  cho client.
- **Cả 3 tool đều chạy ở CLIENT** (đọc dữ liệu công khai, đúng mục 2 tài
  liệu: "tool đọc dữ liệu công khai → client"). `SERVER_TOOL_DECLARATIONS`
  để rỗng (Nhóm B tạm hoãn) — cơ chế server-tool-loop VẪN giữ nguyên trong
  `server.js` (đã kiểm chứng hoạt động đúng ở bản trước với tool
  `kiem_tra_uu_dai_thanh_vien` demo), chỉ cần thêm khai báo là dùng lại được
  ngay khi bàn tới Nhóm B.
- **2 lịch sử tách biệt** (mục 4): `apiHistory` (đúng khuôn Gemini `contents`)
  và `displayMessages` (có thêm trạng thái tạm: đang gõ, thẻ sản phẩm đẹp).
- **Chốt chặn vòng lặp**: `SERVER_TOOL_ROUND_LIMIT = 3` + `CLIENT_TOOL_ROUND_LIMIT = 3`,
  độc lập nhau. Khi client chạm trần mà vẫn còn `functionCall` dở dang, tự
  chốt bằng 1 `functionResponse` báo lỗi giả — tránh lịch sử API bị hỏng
  (bug thật đã gặp + đã vá ở bản trước, xem lịch sử session).
- **Mã lỗi relay rõ ràng**: 400/405/500/502. **Timeout** 45s (tăng từ 30s —
  model "thinking" đôi khi cần nhiều thời gian hơn, đã gặp timeout thật lúc
  test).
- **Guardrail an toàn**: đã test đối kháng qua bộ 30 câu ở `prompt-eval/`
  (30/30 pass) — không lộ prompt, không đáp trả xúc phạm, không cam kết y tế,
  không bị dẫn dắt lạc đề.

## Model dùng + tự chuyển model khi hết quota

`gemini-3.5-flash-lite` (đọc từ `.env`, đổi được qua `GEMINI_MODEL`). Lý do
đổi từ `gemini-3.6-flash`: model đó free-tier chỉ 20 request/NGÀY (không
phải /phút — đã xác minh bằng cách chờ đúng thời gian đề xuất nhiều lần vẫn
429), hết quota giữa buổi test nhiều lần gây gián đoạn. `gemini-3.5-flash-lite`
thuộc nhóm "lite" — quota rộng rãi hơn hẳn, chất lượng trả lời tương đương
(đã test lại y hệt bộ câu hỏi tool-calling, kết quả đúng/grounded như model cũ).

**Cơ chế dự phòng** (`server.js`, `MODEL_FALLBACK_CHAIN`): nếu model đang
dùng bị lỗi 429 (hết quota/rate-limit), server TỰ ĐỘNG chuyển sang model kế
tiếp trong chuỗi, không cần sửa code/restart:

```
gemini-3.5-flash-lite → gemini-3.1-flash-lite → gemini-3.6-flash
```

- 2 model đầu đều thuộc nhóm "lite" (quota rộng), model cuối chất lượng cao
  hơn nhưng quota rất hẹp — chỉ dùng khi cả 2 model lite phía trên đều cạn
  (khó xảy ra, coi như lưới an toàn cuối).
- Request tiếp theo sau khi đã chuyển sẽ đi THẲNG vào model dự phòng, không
  phí công thử lại model đã biết cạn quota (chỉ reset về model đầu khi
  restart server — quota reset theo ngày nên khởi động lại vào hôm sau là ổn).
- Đã test thật: cố tình đặt model đầu = model đã biết hết quota → xác nhận
  server tự log cảnh báo + chuyển model + request vẫn trả 200 bình thường;
  request kế tiếp không thử lại model hỏng (không có dòng log 429 mới).

## Thoát kẹt khi chờ quá lâu (client) + timeout server

- **Đo thật độ trễ** với model lite hiện tại: ~0.7-1s/lượt gọi bình thường
  (trước đây với `gemini-3.6-flash` có lúc gần chạm timeout 30-45s) — đổi
  model tuần trước đã giải quyết phần lớn nguyên nhân gốc của việc "trả lời
  lâu".
- **Server** (`GEMINI_TIMEOUT_MS` trong `server.js`): giảm từ 45s → **30s**
  cho mỗi lượt gọi Gemini — vẫn dư dả ~30 lần so với độ trễ thật đo được,
  nhưng không giữ request treo quá lâu một cách vô ích.
- **Client** (`TONG_TIMEOUT_MS` trong `chat-widget.js`): thêm hẳn trần
  **40s** cho TOÀN BỘ 1 lượt hỏi (kể cả khi phải gọi nhiều vòng tool cộng
  dồn) — trước đây `postRelay()` không có timeout nào cả, nếu server treo vì
  bất kỳ lý do gì thì người dùng bị kẹt ở "đang gõ..." vô thời hạn. Giờ hết
  giờ → tự huỷ request (`AbortController`) + hiện ngay "⏱️ Phản hồi mất quá
  lâu nên đã tự huỷ. Bạn bấm gửi lại câu hỏi giúp mình nhé!" + mở khoá lại ô
  nhập/nút gửi ngay lập tức, không cần tải lại trang.
- Nếu abort xảy ra trước khi có bất kỳ vòng tool nào hoàn tất, tự dọn lại
  lượt hỏi dở dang khỏi `apiHistory` — tránh lịch sử API bị lệch/trùng lặp
  nếu người dùng bấm gửi lại đúng câu đó.
- **Đã kiểm chứng cơ chế abort thật** (không chỉ đọc code): dựng 1 server
  giả cố tình không bao giờ phản hồi, xác nhận `AbortController` cắt đúng
  sau đúng thời gian đặt, bắt được lỗi `AbortError` như thiết kế.

## Đã tự kiểm thử

- Toàn bộ luồng tool CLIENT với dữ liệu Supabase THẬT (không qua trình
  duyệt — mô phỏng bằng script Node gọi thẳng relay + REST Supabase, do hết
  quota `gemini-3.6-flash` giữa buổi nên phần cuối test bằng
  `gemini-3.1-flash-lite`, cùng system prompt + tool declarations y hệt):
  - "Yến thô giá bao nhiêu?" → gọi `san_pham.tim_kiem`, trả đúng giá thật
    (300.000đ/400.000đ gốc), nhận biết đúng sản phẩm khác đã hết hàng từ cột
    `stock`.
  - "Có đang sale gì không?" → gọi `flash_sale`, trả lời đúng "chưa có đợt
    nào" (khớp thực tế: đợt sale duy nhất trong DB đã hết hạn từ tháng 7).
  - "Địa chỉ/hotline?" → gọi `thong_tin_cua_hang`, trả đúng địa chỉ/SĐT thật.
  - "Sản phẩm dưới 100.000đ?" → lọc đúng theo `gia_toi_da`, tìm ra sản phẩm
    thật giá 30.000đ.
  - "Cho mã voucher" → (sau khi vá prompt) từ chối đúng, mời liên hệ hotline,
    không gọi nhầm tool `flash_sale`, không bịa mã.
  - Hỏi lạc đề (thời tiết) → từ chối lịch sự như thiết kế.
- Route tĩnh, lỗi 400/405, path traversal — test lại không đổi so với bản
  trước (không đụng phần này).

**Chưa test được**: giao diện qua trình duyệt thật (box dựng sẵn, thẻ sản
phẩm, hiệu ứng) — cần bạn tự mở `http://localhost:8792` kiểm tra bằng mắt.
