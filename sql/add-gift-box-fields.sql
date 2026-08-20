-- ============================================================
--  CHUẨN BỊ SCHEMA CHO HỘP QUÀ TẶNG + TOPPING
-- ------------------------------------------------------------
--  Bước 1/3 của kế hoạch nâng cấp gói quà: thay cơ chế "phụ phí
--  cố định" cũ bằng hộp quà tặng THẬT (là 1 sản phẩm trong
--  products, có ảnh/giá/mô tả riêng), gợi ý đúng mẫu hộp khớp
--  với sản phẩm yến khách đang mua.
--
--  CÁCH DÙNG: dán toàn bộ vào Supabase → SQL Editor → Run.
--  AN TOÀN: chỉ thêm cột (IF NOT EXISTS), không xóa/mất dữ liệu.
--  RLS/GRANT hiện có trên products áp dụng tự động cho cột mới
--  (RLS theo row, không theo cột) — không cần thêm policy.
-- ------------------------------------------------------------
--  Ý NGHĨA CỘT MỚI:
--  - shape: hình dáng hộp — dùng CHUNG cho cả sản phẩm yến (để
--    biết hộp yến hình gì) và hộp quà tặng (để biết hộp quà vừa
--    hình gì). Gợi ý đúng khi 2 giá trị này khớp nhau.
--  - slot_count: CHỈ áp dụng cho category 'hop-qua-tang' — số ô
--    phụ trống trong hộp quà (0/1/2) để bỏ topping kèm theo.
--    Chỉ mang tính hiển thị thông tin, KHÔNG dùng để lọc gợi ý.
--  - category sẽ có thêm 2 giá trị mới dùng ở admin/san-pham.html:
--    'hop-qua-tang' (hộp quà tặng) và 'topping' (đông trùng, táo
--    đỏ, saffron...) — không cần cột riêng, category vốn là text
--    tự do, admin nhập/chọn giá trị mới là dùng được ngay.
-- ============================================================

alter table public.products add column if not exists shape text;
alter table public.products add column if not exists slot_count integer;
