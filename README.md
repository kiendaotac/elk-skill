# appotapay-claude-skills

Claude Code skills dùng nội bộ (chỉ đọc).

| Skill | Dùng để |
|---|---|
| `elk-logs` | Query log prod/dev trên Kibana (ELK) |

Sentry: dùng connector Sentry của Claude, không cần skill.

## Cài đặt

Hướng dẫn đầy đủ (yêu cầu, kiểm tra, xử lý lỗi): xem [INSTALL.md](INSTALL.md). Bản rút gọn:

```bash
git clone <url-repo> ~/work/appotapay-claude-skills
ln -s ~/work/appotapay-claude-skills/skills/elk-logs ~/.claude/skills/elk-logs
```

Cập nhật skill: `git pull`.

## Credential (mỗi người tự tạo, KHÔNG commit)

Credential nằm ngoài repo, mỗi người dùng tài khoản của chính mình: `~/.config/elk-logs/env`.

Skill có sẵn file mẫu `env.example` với giá trị placeholder:

```bash
mkdir -p ~/.config/elk-logs
cp skills/elk-logs/env.example ~/.config/elk-logs/env
chmod 600 ~/.config/elk-logs/env
```

Sau đó mở file trong `~/.config/elk-logs/env` và thay placeholder bằng giá trị thật của bạn.

## Lưu ý

- Repo không chứa host, tài khoản hay mã giao dịch thật: URL Kibana, tài khoản và mẫu index đều nằm trong file env của từng người. Dù vậy vẫn nên để repo **private**.
- Skill truy cập được log prod, có thể chứa PII. Chỉ cấp cho người có quyền xem log prod.
- Không ghi log prod ra file trong repo.
