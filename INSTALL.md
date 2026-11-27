# Hướng dẫn cài đặt skill `elk-logs`

Skill cho Claude Code đọc log prod/dev trên Kibana (ELK). Chỉ đọc, không sửa hay xoá gì.

## 1. Yêu cầu

- Claude Code đã cài và đăng nhập.
- macOS hoặc Linux, shell `bash`/`zsh`.
- Công cụ dòng lệnh: `git`, `curl`, `jq`.
- Có tài khoản Kibana của chính bạn, và biết URL Kibana của prod và dev (hỏi người quản lý ELK).
- Được cấp quyền xem log prod. Log có thể chứa dữ liệu cá nhân, chỉ dùng cho việc debug.

Kiểm tra công cụ:

```bash
git --version && curl --version | head -1 && jq --version
```

Thiếu `jq`: macOS `brew install jq`, Ubuntu `sudo apt install jq`.

## 2. Cài skill

```bash
mkdir -p ~/work && cd ~/work
git clone <url-repo> appotapay-claude-skills
mkdir -p ~/.claude/skills
ln -s ~/work/appotapay-claude-skills/skills/elk-logs ~/.claude/skills/elk-logs
chmod +x ~/work/appotapay-claude-skills/skills/elk-logs/elk-logs.sh
```

Thay `<url-repo>` bằng địa chỉ repo của team. Dùng `ln -s` (symlink) để sau này `git pull` là skill tự cập nhật.

Nếu không muốn dùng symlink, copy thẳng:

```bash
cp -R ~/work/appotapay-claude-skills/skills/elk-logs ~/.claude/skills/elk-logs
```

Cách này phải copy lại mỗi lần cập nhật.

## 3. Tạo file credential

Credential nằm ngoài repo, không bao giờ commit.

```bash
mkdir -p ~/.config/elk-logs
cp ~/work/appotapay-claude-skills/skills/elk-logs/env.example ~/.config/elk-logs/env
chmod 600 ~/.config/elk-logs/env
```

Mở file và thay placeholder bằng giá trị thật của bạn:

```bash
open -e ~/.config/elk-logs/env      # macOS
# hoặc: nano ~/.config/elk-logs/env
```

Nội dung cần điền:

```bash
ELK_PROD_URL=...            # URL Kibana prod
ELK_PROD_USER=...           # tài khoản Kibana prod
ELK_PROD_PASS=...
ELK_PROD_INDEX_PATTERN=...  # mẫu index theo service, dùng {service} làm chỗ thay tên
ELK_DEV_URL=...             # URL Kibana dev
ELK_DEV_USER=...
ELK_DEV_PASS=...
ELK_DEV_INDEX_PATTERN=...
```

Ví dụ mẫu index: `prefix-{service}-*`. Khi bạn đứng trong một git repo, `{service}` được thay bằng tên repo. Muốn xem service khác thì thêm `--service <tên>`.

Nếu có API key thì dùng `ELK_PROD_API_KEY` / `ELK_DEV_API_KEY` thay cho user/pass (API key được ưu tiên). Có thể đặt thêm `ELK_PROD_INDEX` / `ELK_DEV_INDEX` làm index dự phòng khi không đứng trong git repo.

Lưu ý bảo mật:
- Không dán credential vào chat với Claude hay vào ticket.
- Không để file `env` trong repo. `.gitignore` đã chặn `.env`, nhưng file này nằm ở `~/.config` nên vốn đã ngoài repo.
- Lỡ lộ password thì đổi ngay.

## 4. Kiểm tra cài đặt

```bash
~/.claude/skills/elk-logs/elk-logs.sh dev views <service-name> | head -3
~/.claude/skills/elk-logs/elk-logs.sh dev count '*' --since 1h
```

Kết quả mong đợi: danh sách data view ở lệnh đầu, một con số ở lệnh sau.

Khởi động lại Claude Code (hoặc mở session mới) để nó nhận skill, rồi thử hỏi:

> Dùng skill elk-logs, đếm số log lỗi của <service-name> trên dev trong 1 giờ qua.

## 5. Cách dùng nhanh

```bash
S=~/.claude/skills/elk-logs/elk-logs.sh
$S prod search '<transaction_id>' --since 1d --asc          # log 1 giao dịch theo thứ tự thời gian
$S prod search '<request_id>' --since 1d --asc            # toàn bộ log 1 request theo request id
$S dev  search 'SyncTransactionPendingBaseCommand' --from 2026-10-12T03:00:00Z --to 2026-10-12T04:00:00Z
$S prod count  '"Invalid payment method"' --since 1d
```

Quy tắc dùng:
- Index tự suy ra từ tên git repo bạn đang đứng. Service khác thì thêm `--service <tên-repo>`, hoặc `--index`.
- Luôn giới hạn thời gian và `--size`, vì log prod rất lớn. Bắt đầu hẹp (mã giao dịch và 1 ngày), mở rộng dần.
- `@timestamp` là UTC, giờ trong message là giờ VN (+7).
- Chỉ tóm tắt phần liên quan khi báo cáo, không dump log dài và không ghi log prod ra file trong repo.

## 6. Cập nhật và gỡ cài đặt

Cập nhật (nếu dùng symlink):

```bash
cd ~/work/appotapay-claude-skills && git pull
```

Gỡ:

```bash
rm ~/.claude/skills/elk-logs                 # chỉ xoá symlink hoặc thư mục skill
rm -rf ~/.config/elk-logs                    # xoá credential nếu không dùng nữa
```

## 7. Xử lý lỗi thường gặp

| Lỗi | Nguyên nhân và cách xử lý |
|---|---|
| `Missing Kibana URL` / `Missing index pattern` | Thiếu `ELK_<ENV>_URL` hoặc `ELK_<ENV>_INDEX_PATTERN` trong file env. Kiểm tra lại bước 3 |
| `Missing credentials: set ELK_..._API_KEY or ..._USER/..._PASS` | File `~/.config/elk-logs/env` chưa có hoặc còn placeholder. Kiểm tra lại bước 3 |
| `curl: (22) ... 401` | Sai user/pass, hoặc tài khoản chưa có quyền. Thử đăng nhập Kibana bằng trình duyệt |
| `curl: (22) ... 403` | Tài khoản không có quyền đọc index đó. Hỏi người quản lý ELK |
| `curl: (6)` / `(7)` | Không kết nối được host. Kiểm tra VPN hoặc mạng nội bộ cho host dev |
| `jq: command not found` | Cài `jq` (bước 1) |
| `Permission denied` khi chạy script | `chmod +x` cho `elk-logs.sh` (bước 2) |
| Kết quả `0` dù chắc chắn có log | Sai index. Chạy `views <tên-service>` để tìm index, rồi dùng `--index`. Một số pattern có thể rỗng hoặc không có quyền đọc |
| `_cat/indices` không dùng được | Tài khoản không có quyền `monitor`. Dùng `views` để tìm index |
| Claude không nhận skill | Mở session mới. Kiểm tra `~/.claude/skills/elk-logs/SKILL.md` có tồn tại, và symlink không bị hỏng (`ls -la ~/.claude/skills/`) |
