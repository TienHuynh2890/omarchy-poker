# Hướng dẫn cài đặt & sử dụng Omarchy Poker

Tài liệu chi tiết cho widget **Poker** (Texas Hold'em heads-up vs AI + roulette sinh tử) trên thanh trạng thái Omarchy.

- Repo: https://github.com/TienHuynh2890/omarchy-poker
- Plugin id: `dartc.poker`
- Yêu cầu: Omarchy có shell plugin `schemaVersion: 1`. Không cần build, không cần cài thêm gì.

---

## 1. Cài đặt

### Cách A — Dùng lệnh Omarchy (khuyến nghị)

```bash
omarchy plugin add https://github.com/TienHuynh2890/omarchy-poker.git --enable
```

Lệnh này sẽ:

1. Clone repo vào `~/.config/omarchy/plugins/dartc.poker/`
2. Validate `manifest.json`
3. Cài plugin và bật widget lên bar (mặc định ở `centerEnd`, cạnh đồng hồ)

Nếu không muốn bật ngay, bỏ `--enable`:

```bash
omarchy plugin add https://github.com/TienHuynh2890/omarchy-poker.git
omarchy plugin enable dartc.poker
```

### Cách B — Clone thủ công

```bash
git clone https://github.com/TienHuynh2890/omarchy-poker.git \
  ~/.config/omarchy/plugins/dartc.poker
omarchy plugin enable dartc.poker
```

### Cách C — Qua giao diện

Mở **Omarchy menu → Plugin**, tìm **Poker** rồi bật.

### Kiểm tra sau khi cài

```bash
omarchy plugin list | grep poker
```

Kết quả mong đợi có dạng:

```
dartc.poker    enabled    third-party bar-widget    Poker
```

Icon **♠** sẽ xuất hiện trên bar. Nếu chưa thấy, xem mục [Xử lý sự cố](#6-xử-lý-sự-cố).

---

## 2. Đặt vị trí widget

Di chuyển sang section khác trên bar:

```bash
omarchy bar move dartc.poker --section right
```

Các section hợp lệ: `left`, `centerBegin`, `center`, `centerEnd`, `right`, `tray`.

Hoặc sửa trực tiếp `~/.config/omarchy/shell.json` (shell tự reload khi lưu).

---

## 3. Cách chơi

- Click icon **♠** để mở bàn.
- Click chuột phải icon để vào ván mới ngay.
- Mỗi bên khởi đầu **1.000 chip**, blinds **10/20**.
- Bạn là người chơi, đối thủ là AI.

### Phím tắt khi bàn đang mở

| Phím | Hành động |
|------|-----------|
| `F` | Fold (bỏ bài) |
| `J` hoặc `↓` | Check / Call |
| `K` hoặc `↑` | Raise (+40) |
| `A` | All-in |
| `N` | Ván mới |
| `Space` hoặc `B` | Quay roulette khi đến lượt bạn |

### Roulette sinh tử

Khi một bên hết chip sau khi ván kết thúc:

- Bên đó phải quay roulette. Lần đầu tỉ lệ **1/6**, mỗi lần sống sót tăng thêm 1 viên đạn (**2/6**, **3/6**, … tối đa **6/6**).
- **Sống sót:** được cộng lại **500 chip** và chơi tiếp.
- **Trúng đạn:** thua chung cuộc (bạn chết → game over; AI chết → bạn thắng).
- Khi đến lượt bạn quay, bấm `Space`/`B` hoặc click vào bàn để quay; AI tự quay.

---

## 4. Đổi độ khó AI

```bash
omarchy-shell dartc.poker setAiLevel 0   # 0 = normal (mặc định)
omarchy-shell dartc.poker setAiLevel 1   # 1 = easy
omarchy-shell dartc.poker setAiLevel 2   # 2 = hard
```

Mức đã chọn được giữ lại qua các ván và lần khởi động shell sau.

---

## 5. Dữ liệu và reset

| Dữ liệu | Đường dẫn |
|---------|-----------|
| Ván đang chơi | `~/.local/state/dartc.poker/state.json` |
| Top 3 điểm cao | `~/.local/state/dartc.poker/scores.json` |

- Ván đang chơi được tự lưu và khôi phục khi mở lại shell.
- Không có gì được ghi vào thư mục plugin, nên `omarchy plugin update` không bao giờ conflict.
- **Reset toàn bộ** (mất ván đang chơi + điểm cao):

  ```bash
  rm -rf ~/.local/state/dartc.poker
  ```

  Sau đó mở lại widget, ván mới sẽ tự bắt đầu.

> Bản cũ lưu điểm trong `~/.config/omarchy/plugins/dartc.poker/scores.json`. Khi chạy bản mới, file này được tự động copy sang `~/.local/state/dartc.poker/scores.json` rồi xoá khỏi thư mục plugin.

---

## 6. Xử lý sự cố

### Widget không hiện trên bar

```bash
omarchy plugin list | grep poker        # phải là enabled
omarchy plugin enable dartc.poker       # bật lại nếu đang disabled
omarchy-shell shell rescanPlugins       # nạp lại plugin
```

Nếu vẫn không thấy, restart shell:

```bash
omarchy restart shell
```

### Kiểm tra plugin có hợp lệ không

```bash
omarchy plugin validate ~/.config/omarchy/plugins/dartc.poker
```

Kết quả `VALID` (exit 0) là đúng.

### Widget mở nhưng không phản hồi phím

Click vào bàn một lần để lấy focus, rồi dùng `F` / `J` / `K` / `A`.

### Muốn xem lỗi QML

Chạy shell ở foreground để đọc log:

```bash
omarchy restart shell
```

Log lỗi QML thường xuất hiện ngay trên terminal đang chạy shell hoặc trong journal của phiên Hyprland.

### Cài lại từ đầu

```bash
omarchy plugin remove dartc.poker --yes
omarchy plugin add https://github.com/TienHuynh2890/omarchy-poker.git --enable
```

---

## 7. Cập nhật và gỡ

```bash
omarchy plugin update dartc.poker   # git pull bản mới nhất
omarchy plugin remove dartc.poker   # gỡ plugin (giữ nguyên dữ liệu trong ~/.local/state)
```

Gỡ sạch cả dữ liệu:

```bash
omarchy plugin remove dartc.poker --yes
rm -rf ~/.local/state/dartc.poker
```

---

## 8. Phát triển / tuỳ biến

Mã nguồn nằm ngay trong thư mục plugin:

```
~/.config/omarchy/plugins/dartc.poker/
├── manifest.json   # khai báo plugin
├── Panel.qml       # giao diện, hiệu ứng, roulette, phím tắt
├── Model.js        # engine Texas Hold'em + AI + roulette
└── README.md
```

- Sửa `Panel.qml` hoặc `Model.js`, lưu lại — shell hot-reload.
- Nếu thay đổi không áp dụng: `omarchy-shell shell rescanPlugins` hoặc `omarchy restart shell`.
- Trước khi push, chạy:

  ```bash
  cd ~/.config/omarchy/plugins/dartc.poker
  omarchy plugin validate .
  git add -A && git commit -m "mô tả thay đổi" && git push
  ```

---

## 9. Ghi chú kỹ thuật

- Plugin chạy trong tiến trình `omarchy-shell` (Quickshell), không sandbox — chỉ cài từ nguồn bạn tin.
- Không dùng mạng, không chạy lệnh hệ thống ngoài `mkdir`/`cp`/`rm` để tạo và migrate thư mục state một lần.
- Toàn bộ chữ trong game là tiếng Việt.
- Giấy phép MIT.
