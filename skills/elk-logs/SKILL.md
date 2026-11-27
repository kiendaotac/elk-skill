---
name: elk-logs
description: Đọc log prod/dev của mọi service từ Kibana/ELK để debug, dùng được ở mọi project. Dùng khi cần xem log thật của một giao dịch (transaction_id, vendor_ref, order_id), lỗi cron/sync/queue, exception trên prod hoặc dev, hoặc khi user dán một dòng log và hỏi nguyên nhân.
---

# ELK logs (read-only)

- Kibana prod/dev: URL đặt trong env (`ELK_PROD_URL`, `ELK_DEV_URL`), basic auth hoặc API key.
- Script: `~/.claude/skills/elk-logs/elk-logs.sh` — chỉ cho phép endpoint đọc (`_search`, `_count`, `_cat/indices`, `_mapping`).
- Credential ở `~/.config/elk-logs/env` (chmod 600), user tự điền. KHÔNG đọc/in file này, KHÔNG hỏi user dán credential vào chat.

## Cách dùng

Index tự suy từ tên git repo đang đứng, theo mẫu `ELK_PROD_INDEX_PATTERN` / `ELK_DEV_INDEX_PATTERN` trong env (`{service}` được thay bằng tên repo).
Service khác thì `--service <repo-name>`; tên lệch convention thì tra `views` rồi dùng `--index`.

```bash
S=~/.claude/skills/elk-logs/elk-logs.sh
$S prod views <service-name>                           # tìm index pattern (không có quyền _cat/indices)
$S prod search '<transaction_id>' --since 1d --asc     # log 1 GD theo thứ tự thời gian
$S prod search '<request_id>' --since 1d --asc # theo request id [PG...] để xem trọn 1 request
$S prod search '"sync failed" AND <transaction_id>' --service <service-name> --since 6h --size 200
$S dev  search 'SyncTransactionPendingBaseCommand' --from 2026-10-12T03:00:00Z --to 2026-10-12T04:00:00Z
$S prod count  '"Invalid payment method"' --since 1d
```

- Mỗi dòng log Laravel có request id dạng `[<request_id>]` → search id đó để lấy toàn bộ log của request.
- `@timestamp` là UTC; giờ trong message là giờ VN (+7).
- `views` trả về data view của Kibana (index pattern), một số pattern có thể rỗng/không có quyền đọc → count = 0.

## Quy tắc

- Luôn giới hạn thời gian (`--since`/`--from`) và `--size` hợp lý, prod log lớn.
- Bắt đầu hẹp (mã GD + 1d), rộng dần khi không thấy.
- Log có thể chứa PII/thẻ: chỉ tóm tắt phần liên quan khi trả lời, không dump nguyên log dài, không ghi log prod ra file trong repo.
- Tài khoản nên chỉ có quyền read. Nếu không tạo được API key thì dùng user/pass; không có quyền `_cat/indices` thì dùng `views` để tìm index.
