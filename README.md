# Omarchy Poker

Widget poker **Texas Hold'em heads-up vs AI** cho thanh trạng thái [Omarchy](https://omarchy.org/), kèm màn **roulette kiểu Liar's Bar** khi một bên hết chip.

https://github.com/TienHuynh2890/omarchy-poker

## Tính năng

- Texas Hold'em heads-up: blinds 10/20, mỗi bên khởi đầu 1.000 chip.
- AI 3 mức: `0` normal, `1` easy, `2` hard.
- **Roulette sinh tử**: hết chip thì quay roulette 1/6, sống sót được +500 chip; mỗi lần sống sót tăng thêm một viên đạn (tối đa 6/6).
- Lưu ván đang chơi, tự động vào lại sau khi khởi động shell.
- Bảng top 3 điểm cao.
- Hiệu ứng chip, pot, lật bài, suspense roulette.
- Giao diện tiếng Việt, theo theme Omarchy (màu, font, animation của shell).

## Yêu cầu

- Omarchy có shell plugin `schemaVersion: 1` (manifest của repo này).
- Không cần build, không cần dependency ngoài.

## Cài đặt

Cách chuẩn (Omarchy tự clone, validate rồi cài):

```bash
omarchy plugin add https://github.com/TienHuynh2890/omarchy-poker.git --enable
```

Nếu bỏ `--enable`, bật sau bằng:

```bash
omarchy plugin enable dartc.poker
```

Hoặc chọn trong **Omarchy menu → Plugin**.

Cài thủ công bằng `git clone`:

```bash
git clone https://github.com/TienHuynh2890/omarchy-poker.git \
  ~/.config/omarchy/plugins/dartc.poker
omarchy plugin enable dartc.poker
```

Sau khi bật, icon ♠ xuất hiện trên bar (mặc định ở `centerEnd`). Di chuyển bằng:

```bash
omarchy bar move dartc.poker --section right
```

## Cập nhật và gỡ

```bash
omarchy plugin update dartc.poker   # git pull bản mới
omarchy plugin remove dartc.poker   # gỡ plugin
```

## Sử dụng

- Click icon ♠ để mở bàn; click chuột phải để vào ván mới.
- Phím tắt khi bàn đang mở:

  | Phím | Hành động |
  |------|-----------|
  | `F` | Fold |
  | `J` / `↓` | Check / Call |
  | `K` / `↑` | Raise (+40) |
  | `A` | All-in |
  | `N` | Ván mới |
  | `Space` / `B` | Quay roulette khi đến lượt bạn |

- Đổi độ khó AI qua IPC:

  ```bash
  omarchy-shell dartc.poker setAiLevel 0   # 0 normal, 1 easy, 2 hard
  ```

## Dữ liệu

Không có gì được ghi vào thư mục plugin, nên `omarchy plugin update` luôn sạch:

- Ván đang chơi: `~/.local/state/dartc.poker/state.json`
- Điểm cao: `~/.local/state/dartc.poker/scores.json`

Xoá thư mục `~/.local/state/dartc.poker/` để reset toàn bộ.

## Phát triển

Sửa `Panel.qml` / `Model.js` trong `~/.config/omarchy/plugins/dartc.poker/` — shell tự hot-reload. Kiểm tra manifest trước khi publish:

```bash
omarchy plugin validate .
```

## Giấy phép

MIT — xem [LICENSE](LICENSE).

---

## English

A heads-up Texas Hold'em bar widget for the Omarchy shell, with a Russian-roulette tiebreaker inspired by Liar's Bar. The in-game UI is in Vietnamese.

**Features:** heads-up Hold'em (10/20 blinds, 1,000 starting chips), three AI levels, survival roulette when a player busts (1/6 odds, +500 chips and one extra bullet per survival, up to 6/6), persistent game state and top-3 scores, Omarchy theme-aware UI.

**Install:**

```bash
omarchy plugin add https://github.com/TienHuynh2890/omarchy-poker.git --enable
```

Or clone manually into `~/.config/omarchy/plugins/dartc.poker` and run `omarchy plugin enable dartc.poker`.

**Update / remove:** `omarchy plugin update dartc.poker`, `omarchy plugin remove dartc.poker`.

**Controls:** `F` fold, `J`/`↓` check/call, `K`/`↑` raise, `A` all-in, `N` new hand, `Space`/`B` spin the roulette. Right-click the ♠ icon for a new hand. Set AI level with `omarchy-shell dartc.poker setAiLevel {0|1|2}`.

**Data:** `~/.local/state/dartc.poker/state.json` and `scores.json`. The plugin folder stays clean, so git updates never conflict.

**Requirements:** Omarchy with `schemaVersion: 1` shell plugins. No build step.

**License:** MIT.
