# system-monitor

Gadget เล็กๆ มุมขวาล่างจอ แสดง CPU / RAM / Disk / Network ลอยทับทุกหน้าต่าง (Windows, PowerShell + WPF, ไม่ต้องติดตั้งอะไร)

## ติดตั้ง (พิมพ์บรรทัดเดียวใน cmd)

```
powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.2.0/install.ps1 | iex"
```

- ติดตั้งที่ `%LOCALAPPDATA%\Programs\system-monitor` ตั้งให้เปิดพร้อม Windows และเปิดให้ทันที ไม่ต้องใช้สิทธิ์ admin
- ระหว่างติดตั้งจะถามว่าจะให้แสดง usage ของ Claude Code (5hr / Week) ไหม ถ้าตอบ y จะเพิ่ม `statusLine` ใน `~\.claude\settings.json` (สำรองไฟล์เดิมไว้ และข้ามให้ถ้ามี statusLine อยู่แล้ว) ถ้าไม่ตอบ/ตอบ n แถวนี้จะขึ้น `--`
- อัปเดต: ตั้งแต่ v1.2.0 โปรแกรมเช็กเวอร์ชันใหม่เองวันละครั้งจาก GitHub (เรียก api.github.com เท่านั้น) และ**ติดตั้งให้เองโดยอัตโนมัติ** แล้วรีสตาร์ท gadget ค่า Settings ไม่หาย ถ้าไม่อยากให้ติดตั้งเอง ให้เอาติ๊กออกที่ Settings -> "Install updates automatically" (จะเหลือป้าย `Update` ให้กดเอง) หรือปิดการเช็กทั้งหมดที่ "Check for updates automatically" ถ้าติดตั้งอัตโนมัติไม่สำเร็จจะลองใหม่ได้ไม่เกินวันละครั้ง หรือรันคำสั่งติดตั้งซ้ำด้วยมือก็ได้ (เวอร์ชันก่อน v1.2.0 ต้องรันคำสั่งเวอร์ชันใหม่ด้วยมือหนึ่งครั้ง)
- ถอนการติดตั้ง: `powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.2.0/uninstall.ps1 | iex"`
- สคริปต์เป็นข้อความธรรมดา เปิดอ่านก่อนรันได้ที่ลิงก์ในคำสั่ง ต้องใช้ Windows 10/11 (PowerShell 5.1 ที่มากับเครื่อง)

## การใช้งาน

- ตั้งค่า: คลิกขวาที่ gadget -> Settings... ปรับความโปร่งใส (0-90%), ซ่อน/แสดงปฏิทิน, ซ่อน/แสดงแถว Claude usage (บันทึกอัตโนมัติที่ `%LOCALAPPDATA%\system-monitor\settings.json` ลบไฟล์นี้เพื่อกลับค่าเริ่มต้น)
- ปฏิทินตั้งโต๊ะ (เดือนไทย ปี พ.ศ.): คลิก `<` `>` เปลี่ยนเดือน, คลิกชื่อเดือนเพื่อกลับเดือนปัจจุบัน
- แถว 5hr / Week แสดง usage ของ Claude Code (ต้องตั้ง statusLine ชี้ไป `claude-usage-hook.ps1` ใน `~/.claude/settings.json`)
- พับ/ขยาย gadget: กดปุ่ม − มุมขวาบนเพื่อพับเหลือแถบเล็ก (CPU / RAM) แล้วคลิกที่แถบเพื่อขยายกลับ (จำสถานะไว้)
- ซ่อนทั้งหมด: คลิกขวา -> Hide แล้วคลิกไอคอนที่ system tray เพื่อแสดงกลับ (คลิกขวาที่ไอคอนมีเมนู Show/Hide, Settings, Exit) ถ้าไอคอนซ่อนอยู่ใน `^` ให้ลากออกมาปักไว้ ซ่อนแล้วจะแสดงกลับเองทุกครั้งที่เปิดโปรแกรมใหม่
- เปิด: ดับเบิลคลิก `start-monitor.vbs` (ไม่มีหน้าต่าง console)
- ปิด: คลิกขวาที่ gadget -> Exit
- เปิดตอนเปิดเครื่อง: `powershell -File install-startup.ps1` (ยกเลิกด้วย `-Remove`)
- ดูค่าเป็นข้อความ (ไม่เปิด UI): `powershell -File monitor.ps1 -DumpMetrics`

ไฟล์ `.ps1` ต้องเป็น ASCII ล้วน (Windows PowerShell 5.1 อ่านไฟล์ไม่มี BOM เป็น ANSI)
