# Yến Sào Yến Duyên — Quy tắc bắt buộc

Website bán yến sào: HTML/CSS/JS thuần (không build step) + Supabase (Postgres/Auth/Storage).

## Kiến trúc bảo mật (KHÔNG được vi phạm)

1. Mọi ngưỡng số, thuật toán, dữ liệu nhạy cảm liên quan bảo mật PHẢI nằm trong
   Postgres (schema `security`, không nằm trong "Exposed schemas" của Supabase API).
   TUYỆT ĐỐI không hardcode ngưỡng/giới hạn/secret trong file HTML/JS phía client.

2. Code bảo mật phía client CHỈ được đặt trong `js/security-gate.js`.
   Không viết logic bảo mật rải rác vào `main.js`, `cart.js`, hay script inline
   trong các trang — kể cả khi có vẻ "tiện" để làm nhanh.

3. Mọi hành động ghi dữ liệu mới (insert/update/rpc) mà người dùng ẩn danh
   hoặc tài khoản thường có thể gọi tới PHẢI gọi
   `SecurityGate.check(bucket, identifier)` trước khi thực thi, với 1 bucket
   tương ứng đã đăng ký trong `security.rate_limit_config`. Không thêm
   endpoint ghi dữ liệu công khai mới mà bỏ qua bước này.

4. Không bao giờ tin dữ liệu/cờ do client tự gửi lên để quyết định quyền truy
   cập (vd: không dùng `localStorage` để xác nhận ai là admin — bài học từ lỗi
   thật đã gặp: các trang admin cũ chỉ kiểm tra 1 object tự chế trong
   localStorage, ai mở DevTools tạo object đó là vào được giao diện).
   Mọi kiểm tra quyền admin PHẢI xác thực lại phiên Supabase thật +
   `profiles.role` tại chỗ.

5. Mọi bảng mới tạo trong Supabase PHẢI bật RLS và có policy rõ ràng trước khi
   dùng trong code — không được để mặc định "không RLS" (bài học từ lỗi thật:
   bảng `orders` từng không có RLS, ai cũng đọc/sửa được đơn hàng người khác
   qua gọi thẳng REST API).

6. Mọi nội dung do người dùng nhập mà render ra HTML động PHẢI qua hàm `esc()`
   (quy ước đã dùng nhất quán toàn site) để chặn XSS. Không thêm chỗ render
   mới mà bỏ qua bước escape này.

7. Cơ chế rate-limit (`SecurityGate` + `check_rate_limit`) là lớp chống lạm
   dụng, KHÔNG phải biên bảo mật chính — nếu gọi hàm lỗi/mạng lỗi thì PHẢI
   mặc định cho phép (fail-open), không được để lỗi ở lớp này khoá luôn tính
   năng chính của site. Biên bảo mật thật luôn là RLS + xác thực Supabase.

## Tránh xung đột code

8. Khi sửa `js/security-gate.js` hoặc file SQL trong `sql/security-*.sql`:
   CHỈ sửa vì lý do bảo mật (đổi ngưỡng, thêm bucket...). Không tiện tay sửa
   logic nghiệp vụ trong cùng lúc.

9. Khi sửa logic nghiệp vụ ở các trang (giỏ hàng, đặt hàng, đánh giá...):
   KHÔNG động vào dòng gọi `SecurityGate.check(...)` trừ khi mục đích chính
   là thay đổi hành vi bảo mật đó.

10. File SQL mới đặt tên theo đúng quy ước đã có (`add-*.sql`, `fix-*.sql`),
    và mọi thay đổi DB quan trọng phải được ghi chú lại (memory hoặc
    `Mistake/Task.txt`) để không mất dấu vết.

## Quy trình làm việc

11. LUÔN trình bày kế hoạch và xin xác nhận trước khi viết/sửa code — làm
    từng bước một, không tự ý mở rộng phạm vi ngoài những gì đã bàn.

12. Sau khi trình bày xong kế hoạch (kể cả sau khi đã hỏi và nhận đủ câu trả
    lời cho các câu hỏi làm rõ), PHẢI dừng lại và hỏi rõ "bạn duyệt kế hoạch
    này không" — chờ người dùng xác nhận (vd "duyệt", "tiến hành", "ok") rồi
    mới được bắt đầu viết/sửa code. Trả lời xong các câu hỏi làm rõ KHÔNG
    đồng nghĩa là đã duyệt kế hoạch — đây là 2 bước tách biệt, không được gộp
    làm một hay tự suy ra sự đồng ý.
