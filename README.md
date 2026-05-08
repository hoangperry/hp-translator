# Contextual Mac Translator

Menu bar app macOS cho dịch realtime theo ngữ cảnh qua phím tắt toàn hệ thống.

> **Open-source client.** Backend tham chiếu nằm trong repo riêng (closed-source).
> Client chỉ nói chuyện với HTTP endpoint qua [docs/api-contract.md](../docs/api-contract.md), nên có thể ghép với mọi backend tự xây miễn là tuân thủ contract.

## MVP đã có

- Inbound: bôi đen text trong app bất kỳ, bấm `Option-D`, app giả lập `Command-C`, gửi text lên backend, hiển thị bản dịch tiếng Việt bằng floating HUD tại vị trí chuột.
- Outbound Keigo: gõ tiếng Việt trong ô chat, bấm `Command-Return`, app chọn dòng hiện tại, copy, dịch sang tiếng Nhật công sở. Mặc định hiện preview HUD; bấm `Tab` để sửa bản dịch, `Return` để gửi, `Esc` để hủy và phục hồi clipboard.
- Outbound Casual: giống outbound nhưng dùng `Option-Return` và persona tiếng Nhật giao tiếp bạn bè (auto-send, không preview).
- Menu bar app chạy nền bằng AppKit/SwiftUI.
- Global hotkeys bằng Carbon `RegisterEventHotKey`.
- Automation bằng `CGEvent`, clipboard bằng `NSPasteboard`.
- Settings UI để cấu hình backend endpoint, bearer token và glossary.
- API key + glossary lưu trong macOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`); migration một-lần từ `UserDefaults` cũ.
- Focus-guard: nếu app frontmost thay đổi giữa hotkey và paste, workflow bị abort và clipboard được restore.
- First-launch setup cho Accessibility và Input Monitoring; hotkeys chỉ được đăng ký sau khi setup hoàn tất.
- HTTPS-only enforcement cho remote endpoint; `http://` chỉ được cho phép trên loopback (`localhost`, `127.0.0.1`, `::1`).

## Yêu cầu quyền macOS

Mở app lần đầu rồi cấp:

- System Settings -> Privacy & Security -> Accessibility
- System Settings -> Privacy & Security -> Input Monitoring

Accessibility là quyền quan trọng nhất cho thao tác giả lập phím. Input Monitoring được hiển thị theo yêu cầu MVP và hữu ích cho các workflow hotkey/input sâu hơn.

## Chạy development

```bash
swift build
swift run ContextualMacTranslator
```

Nếu chạy trong môi trường sandbox bị lỗi cache SwiftPM, chạy trực tiếp trong terminal macOS bình thường.

## Test

```bash
swift test
```

48 test Swift Testing cho Keychain store, credential migration, clipboard polling, focus guard, preview HUD, endpoint policy, SettingsStore và persona policy.

## Cấu hình endpoint

Sau khi mở app:

1. Mở Settings từ menu bar.
2. Endpoint mặc định: `http://127.0.0.1:8765/translate` (loopback sang backend chạy local). Remote endpoint phải dùng `https://`.
3. Nếu backend yêu cầu bearer auth, dán token vào field "API Key". Token được lưu trong Keychain (không trong UserDefaults).
4. Glossary là mảng `term=preferredTranslation` mỗi dòng một cặp; cũng lưu trong Keychain.

Client gửi `Authorization: Bearer <token>` khi field API key có giá trị, bỏ qua header nếu rỗng.

## Backend

Backend tham chiếu (Python stdlib, đa provider) được phát hành tách rời tại repo `translator-server`. Xem [../docs/api-contract.md](../docs/api-contract.md) để tự xây backend khác.

Provider hỗ trợ trong reference backend: Gemini API, Ollama local, Google Translate Basic, OpenAI-compatible, mock (echo). Khi chạy backend public (non-loopback), server bắt buộc set `TRANSLATOR_TOKEN` hoặc explicit `TRANSLATOR_ALLOW_REMOTE=1`.

## Đóng gói `.app`

```bash
scripts/package_app.sh release
open ".build/app/Contextual Mac Translator.app"
```

## Tạo installer cài vào `/Applications`

```bash
scripts/package_installer.sh
open ".build/installer/Contextual-Mac-Translator-v0.1.2-macos-arm64.pkg"
```

Installer hiện là package unsigned cho local testing; public distribution vẫn cần Developer ID signing + notarization.

Bundle ID hiện tại là placeholder `app.lookerlab.translator`. Trước khi phân phối public phải:

1. Đăng ký Apple Developer Program và sinh "Developer ID Application" certificate.
2. Đổi `CFBundleIdentifier` trong `scripts/package_app.sh` và `keychainService` trong `Sources/ContextualMacTranslator/SettingsStore.swift` sang reverse-DNS thực sự sở hữu.
3. Bổ sung `codesign --options runtime --timestamp` + `xcrun notarytool submit --wait` + `xcrun stapler staple` vào pipeline đóng gói.

## Giới hạn MVP

- Outbound chọn text từ con trỏ về đầu dòng bằng `Command-Shift-Left`; phù hợp với chat input một dòng. App nhiều dòng hoặc editor custom có thể cần selection strategy riêng.
- Client chấp nhận response dạng `translation`, `translatedText`, `outputText`, `output_text`, hoặc OpenAI-style `choices[]`.
- Chưa có cấu hình tùy biến hotkey trong UI; hotkeys đang cố định theo brief.
- Certificate pinning, signing/notarization và Sparkle update channel: M2/M3 roadmap (xem [docs/deliver-report.md](../docs/deliver-report.md)).

## Tài liệu

- [../docs/PRD.md](../docs/PRD.md) — yêu cầu sản phẩm.
- [../docs/define-spec.md](../docs/define-spec.md) — định nghĩa milestone + acceptance criteria.
- [../docs/develop-report.md](../docs/develop-report.md) — báo cáo build M1.
- [../docs/deliver-report.md](../docs/deliver-report.md) — báo cáo deliver M1, danh sách finding, lộ trình M2/M3.
- [../docs/smoke-test-runbook.md](../docs/smoke-test-runbook.md) — runbook smoke test thủ công.
- [../docs/api-contract.md](../docs/api-contract.md) — contract HTTP với backend.
