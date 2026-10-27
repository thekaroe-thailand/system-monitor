# system-monitor

Gadget เล็กๆ มุมขวาล่างจอ แสดง CPU / RAM / Disk / Network ลอยทับทุกหน้าต่าง (Windows, PowerShell + WPF, ไม่ต้องติดตั้งอะไร)

หน้าเว็บสำหรับคัดลอกคำสั่ง (ไทย/อังกฤษ): https://thekaroe-thailand.github.io/system-monitor/

## ติดตั้ง (พิมพ์บรรทัดเดียวใน cmd)

```
powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.2.7/install.ps1 | iex"
```

- ติดตั้งที่ `%LOCALAPPDATA%\Programs\system-monitor` ตั้งให้เปิดพร้อม Windows และเปิดให้ทันที ไม่ต้องใช้สิทธิ์ admin
- ระหว่างติดตั้งจะถามว่าจะให้แสดง usage ของ Claude Code (5hr / Week) ไหม ถ้าตอบ y จะเพิ่ม `statusLine` ใน `~\.claude\settings.json` (สำรองไฟล์เดิมไว้ และข้ามให้ถ้ามี statusLine อยู่แล้ว) ถ้าไม่ตอบ/ตอบ n แถวนี้จะขึ้น `--`
- อัปเดต: ตั้งแต่ v1.2.0 โปรแกรมเช็กเวอร์ชันใหม่เองวันละครั้งจาก GitHub (เรียก api.github.com เท่านั้น) และ**ติดตั้งให้เองโดยอัตโนมัติ** แล้วรีสตาร์ท gadget ค่า Settings ไม่หาย ถ้าไม่อยากให้ติดตั้งเอง ให้เอาติ๊กออกที่ Settings -> "Install updates automatically" (จะเหลือป้าย `Update` ให้กดเอง) หรือปิดการเช็กทั้งหมดที่ "Check for updates automatically" ถ้าติดตั้งอัตโนมัติไม่สำเร็จจะลองใหม่ได้ไม่เกินวันละครั้ง หรือรันคำสั่งติดตั้งซ้ำด้วยมือก็ได้ (เวอร์ชันก่อน v1.2.0 ต้องรันคำสั่งเวอร์ชันใหม่ด้วยมือหนึ่งครั้ง)
- ถอนการติดตั้ง: `powershell -NoProfile -Command "irm https://raw.githubusercontent.com/thekaroe-thailand/system-monitor/v1.2.7/uninstall.ps1 | iex"`
- สคริปต์เป็นข้อความธรรมดา เปิดอ่านก่อนรันได้ที่ลิงก์ในคำสั่ง ต้องใช้ Windows 10/11 (PowerShell 5.1 ที่มากับเครื่อง)

## การใช้งาน

- ตั้งค่า: คลิกขวาที่ gadget -> Settings... ปรับความโปร่งใส (0-90%), ซ่อน/แสดงปฏิทิน, ซ่อน/แสดงแถว Claude usage (บันทึกอัตโนมัติที่ `%LOCALAPPDATA%\system-monitor\settings.json` ลบไฟล์นี้เพื่อกลับค่าเริ่มต้น)
- ปฏิทินตั้งโต๊ะ (เดือนไทย ปี พ.ศ.): คลิก `<` `>` เปลี่ยนเดือน, คลิกชื่อเดือนเพื่อกลับเดือนปัจจุบัน
- แถว 5hr / Week แสดง usage ของ Claude Code (ต้องตั้ง statusLine ชี้ไป `claude-usage-hook.ps1` ใน `~/.claude/settings.json`) ค่าจากทางนี้อัปเดตเฉพาะตอนใช้ผ่าน CLI ถ้าเก่าเกิน 15 นาทีจะเป็นสีเทาพร้อมบอกอายุ (`5% 4h ago`)
- **Live Claude usage (ไม่บังคับ ปิดเป็นค่าเริ่มต้น):** ติ๊กใน Settings เพื่อให้ตัวเลขตรงกับ Claude แม้ใช้ผ่าน VS Code อย่างเดียว โปรแกรมจะอ่าน token ล็อกอินใน `~\.claude\.credentials.json` (อ่านอย่างเดียว ไม่เขียน ไม่ refresh) แล้วถามค่าจาก `api.anthropic.com/api/oauth/usage` ทุก 2 นาที เป็น endpoint ที่ไม่เป็นทางการ อาจเปลี่ยนหรือใช้ไม่ได้เมื่อไหร่ก็ได้ ถ้า token หมดอายุจะถอยกลับไปใช้ค่าจาก CLI
- **Ollama Cloud usage (ไม่บังคับ):** Settings -> ส่วน Ollama Cloud วาง API key จาก https://ollama.com/settings/keys แล้วกด Connect จะมีแถว Ollama Cloud เพิ่มใน gadget (และในแถบเล็กตอนพับ) แพ็กเกจแบบเก่าแสดง 5hr / Week แพ็กเกจรายเดือนแสดง Month (เครดิตที่ใช้ไปของเดือนนี้) ถ้ามีเครดิตที่ซื้อเพิ่มจะขึ้นที่มุมขวาของหัวข้อ ดึงจาก API ทางการ `ollama.com/api/balance` นาทีละครั้ง คีย์เก็บแบบเข้ารหัส (Windows DPAPI ถอดได้เฉพาะ user Windows นี้) ไม่ต้องลงโปรแกรม Ollama ในเครื่อง เอาติ๊ก "Show Ollama Cloud usage" ออกเพื่อซ่อน (หยุดเช็กด้วย คีย์ยังอยู่) กด Disconnect เพื่อลบคีย์
- gadget แบ่ง usage เป็นกลุ่มตามผู้ให้บริการ (Claude / Ollama Cloud) แต่ละกลุ่มมีจุดสีประจำ ใช้สีเดียวกันในแถบเล็กตอนพับ
- พับ/ขยาย gadget: กดปุ่ม − มุมขวาบนเพื่อพับเหลือแถบเล็ก (CPU / RAM) แล้วคลิกที่แถบเพื่อขยายกลับ (จำสถานะไว้)
- ซ่อนทั้งหมด: คลิกขวา -> Hide แล้วคลิกไอคอนที่ system tray เพื่อแสดงกลับ (คลิกขวาที่ไอคอนมีเมนู Show/Hide, Settings, Exit) ถ้าไอคอนซ่อนอยู่ใน `^` ให้ลากออกมาปักไว้ ซ่อนแล้วจะแสดงกลับเองทุกครั้งที่เปิดโปรแกรมใหม่
- เปิด: ดับเบิลคลิก `start-monitor.vbs` (ไม่มีหน้าต่าง console)
- ปิด: คลิกขวาที่ gadget -> Exit
- เปิดตอนเปิดเครื่อง: `powershell -File install-startup.ps1` (ยกเลิกด้วย `-Remove`)
- ดูค่าเป็นข้อความ (ไม่เปิด UI): `powershell -File monitor.ps1 -DumpMetrics`

ไฟล์ `.ps1` ต้องเป็น ASCII ล้วน (Windows PowerShell 5.1 อ่านไฟล์ไม่มี BOM เป็น ANSI)
