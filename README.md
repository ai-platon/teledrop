# TeleDrop

Drag any file to your MacBook's notch — it lands in Telegram.

TeleDrop puts a small drop zone right next to the notch. Start dragging a file, an island slides out, drop it there, and your own Telegram bot sends it to you. Handy for getting a file from your Mac to your phone in two seconds.

## Features

- **Notch drop zone** that appears only while you drag files, with smooth spring animations
- **Anything you can drag**: files, folders, photos, screenshot thumbnails, images from browsers
- **Big files**: up to 49 MB goes as is; bigger files are zipped, and a zip that is still too big is split into `.001`, `.002`… parts (open with 7-Zip, The Unarchiver or Keka, or `cat name.zip.* > name.zip`)
- **3-step setup**: create a bot in @BotFather, paste the token, press Start — TeleDrop finds your chat itself
- **Private**: no servers in between — files go straight from your Mac to Telegram's Bot API
- Plays nice with **Coucou**: slides aside when Coucou's panel is open
- Universal app: Apple Silicon and Intel, macOS 14+

## Install

1. Download `TeleDrop.dmg` from the latest release and drag TeleDrop to **Applications**.
2. Open it. The app isn't notarized by Apple, so macOS will warn you the first time:
   open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
3. Follow the setup window.

## Permissions

| macOS asks for | Why |
|---|---|
| Desktop / Documents / Downloads | to read the file you dropped |
| Screen Recording (only if Coucou is installed) | to see whether Coucou's panel is open and move aside. You can decline — everything else still works. |

## Build from source

```bash
./build.sh      # universal build, installs to /Applications
./dist.sh       # makes dist/TeleDrop.dmg
Tools/make_icon.sh   # regenerates the app icon
```

Requires Xcode Command Line Tools (Swift 5.10+).

## Notes

TeleDrop is an independent project. It is not affiliated with or endorsed by Telegram, Apple or Coucou.
"Telegram" is a trademark of Telegram FZ-LLC. TeleDrop uses the public Telegram Bot API with a bot you create.

## License

MIT — see [LICENSE](LICENSE).
