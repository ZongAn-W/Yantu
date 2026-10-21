# 日历 UI 设计灵感（网络参考）

收集了一批「有设计感」的日历界面，以及和本项目月历相关的可借鉴点。截图见
`.dsh-verify/calendar-inspiration/screens/calendar-ui-moodboard.png`（仅本地研究用，不入库）。

## 参考列表

### 真实产品

- **Notion Calendar** — https://www.notion.com/product/calendar
  无表格线、半透明彩色事件块、大量留白；左侧迷你可切换月份；选中日用实心圆，今天用红点。
  借鉴点：月/周网格可以完全去掉边框，用留白和颜色分层。
- **Timepage（Moleskine）** — https://bonobolabs.com/timepage/
  暗色、日期是大小/深浅不同的圆盘（事件越多越实），今天用描边圈。
  借鉴点：只用「圆 + 明暗」就能表达每天的信息量，和「格内无文字」的诉求完全一致。
- **HEY Calendar** — https://hey.com/calendar/
  手绘箭头、贴纸图标、强色块、周视图；情绪价值很强。
  借鉴点：可以给月份/课程加一点点「手写/贴纸」的个性元素，但不宜照搬。
- **Morgen** — https://www.morgen.so
  暗色时间块 + 分类颜色 + 一条当前时间红线；左侧任务/列表栏。
  借鉴点：右侧计划栏可以做成 G 那样的结构，用课程色区分，并保留「现在」的指示。
- **Fantastical** — https://flexibits.com/fantastical
  网格 + 时间线双视图，密度高但层级清楚；强调自然语言输入。
  借鉴点：月视图保持轻，详情交给日视图。

### 设计案例合集

- **Eleken：33 Calendar UI Examples** — https://www.eleken.co/blog-posts/calendar-ui
  含 Privado（日历热力图）、PrimePro（月/周任务视图）、Whering（穿搭月历）、Instagram
  归档（月历缩略图）、Co-Star（符号月历）、Tubik（渐变活动日历）等。
- **Justinmind：Best Calendar App Designs** — https://www.justinmind.com/blog/best-calendar-app-designs-and-how-to-prototype-your-own/
- **Dribbble 日历标签** — https://dribbble.com/tags/calendar-ui
  - Minimal Calendar UI Concept — https://dribbble.com/shots/27456980-Calendar-App-Minimal-UI-Concept
  - Calendar UI — Holidays & Blocked Dates — https://dribbble.com/shots/27715290-Calendar-UI-Design-Holidays-Blocked-Dates
  - Minimal Calendar Ui Design — https://dribbble.com/shots/22529308-Minimal-Calendar-Ui-Design
  - Calendar Dashboard — https://dribbble.com/shots/24897741-calendar-dashboard

## 对本项目月历的三个可落地方向

1. **热力月历（Privado 式）**：每日格子按计划负荷上 0–4 级底色，今天圆环、选中描边；右侧栏
   看详情。最接近现在的 I 方案，但把「负荷」真正做成可读的图。
2. **学习马赛克（Instagram 归档 / Whering 式）**：格子里不放文字，用课程色块拼贴，色块面积
   与计划分钟成正比；一个月像一张课程构成海报。最独特，也最贴合「格内无文字」。
3. **氛围月历（Timepage / Tubik 式）**：保留极简结构，给月份加一层柔和渐变或季节色；
   圆盘表示计划量，选中/今天用描边区分。视觉最「有设计感」，但会打破当前 Mist Ink 的克制。

推荐先试 2（学习马赛克），差异化最大；如果担心信息可读性，选 1 最稳。
