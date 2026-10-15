import { useEffect, useRef, useState } from "react";
import {
  NavLink,
  Navigate,
  Route,
  Routes,
  useLocation,
} from "react-router-dom";
import {
  BarChart3,
  CalendarDays,
  CheckCircle2,
  ChevronRight,
  Cloud,
  Download,
  GraduationCap,
  ListChecks,
  Menu,
  Settings,
  X,
  LogIn,
  LogOut,
  Upload,
  RefreshCw,
} from "lucide-react";
import {
  PlannerProvider,
  usePlanner,
  syncStatusNames,
  type SyncStatus,
} from "./store";
import { Dashboard, Tasks, Calendar, Progress } from "./pages";
import { Modal } from "./components";
import { now } from "./utils";
import { createInitialData, localDate } from "./data";
import { createPlannerStorage, isDesktopRuntime, normalizeStorageData } from "./storage";
import { Onboarding } from "./onboarding";

function Shell() {
  const location = useLocation();
  const {
    data,
    syncStatus,
    syncMessage,
    cloudConfigured,
    apiConfigured,
    apiUser,
    apiOnboardingComplete,
    signIn,
    signUp,
    signOut,
    setData,
    user,
    storageStatus,
    storageMessage,
    storageBlocked,
    retryStorage,
    restoreData,
  } = usePlanner();
  const [transferMessage, setTransferMessage] = useState("");
  const recoveryInputRef = useRef<HTMLInputElement>(null);
  const storageStatusText = {
    loading: "正在读取本机数据",
    saving: "正在保存到本机",
    saved: "已保存到本机",
    error: "本机存储异常",
    recovered: "已从备份恢复",
  }[storageStatus];
  const [open, setOpen] = useState(false),
    [auth, setAuth] = useState(false),
    [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [authMode, setAuthMode] = useState<"login" | "signup">("login"),
    [authError, setAuthError] = useState("");
  useEffect(() => {
    if (apiConfigured && !apiUser) setAuth(true);
  }, [apiConfigured, apiUser]);
  const nav = [
    { to: "/", label: "今日", icon: CheckCircle2 },
    { to: "/calendar", label: "日历", icon: CalendarDays },
    { to: "/tasks", label: "事项", icon: ListChecks },
    { to: "/progress", label: "进度", icon: BarChart3 },
    { to: "/settings", label: "设置", icon: Settings },
  ];
  async function exportData() {
    try {
      await createPlannerStorage().exportJson(data);
      setTransferMessage("");
    } catch (error) {
      setTransferMessage(`导出失败：${String(error)}。请重新选择可写入的位置。`);
    }
  }
  async function importData(file?: File) {
    try {
      const value = file ? JSON.parse(await file.text()) : await createPlannerStorage().importJson();
      if (value === null) return;
      const normalized = normalizeStorageData(value);
      if (!normalized) throw new Error("文件格式不正确，原有数据已保留。");
      await restoreData(normalized);
      setTransferMessage("数据已恢复并保存到本机。");
    } catch (error) {
      setTransferMessage(`恢复失败：${String(error)}`);
    }
  }
  const authContent = !cloudConfigured ? (
    <>
      <p>未配置 Supabase，当前使用本地 Demo。</p>
      <p className="muted">
        配置项：VITE_SUPABASE_URL、VITE_SUPABASE_ANON_KEY（或
        VITE_SUPABASE_PUBLISHABLE_KEY）
      </p>
      <div className="sync-local">
        <span className="status-dot demo" />
        {storageStatusText}
      </div>
    </>
  ) : user ? (
    <>
      <p>{apiConfigured ? "已登录，课程、事项、每日计划和实际学习记录保存在服务器。" : "已登录，事项、每日计划和实际学习记录会通过 Supabase 同步。"}</p>
      <button
        className="danger"
        onClick={async () => {
          await signOut();
          setAuth(false);
        }}
      >
        <LogOut size={16} />
        退出登录
      </button>
    </>
  ) : (
    <>
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setAuthError("");
          try {
            if (authMode === "login") await signIn(email, password);
            else await signUp(email, password);
            setAuth(false);
          } catch (err) {
            setAuthError(err instanceof Error ? err.message : String(err));
          }
        }}
      >
        <label>
          邮箱
          <input
            type="email"
            required
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </label>
        <label>
          密码
          <input
            type="password"
            minLength={6}
            required
            autoComplete={
              authMode === "login" ? "current-password" : "new-password"
            }
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </label>
        {authError && (
          <p className="error" role="alert">
            {authError}
          </p>
        )}
        <footer className="dialog-actions">
          <button
            type="button"
            onClick={() =>
              setAuthMode(authMode === "login" ? "signup" : "login")
            }
          >
            {authMode === "login" ? "创建账号" : "返回登录"}
          </button>
          <button className="primary" type="submit">
            <LogIn size={16} />
            {authMode === "login" ? "登录" : "注册"}
          </button>
        </footer>
      </form>
      <p className="muted">
        未登录时仍可在本机使用 Demo，登录后会把当前计划同步到云端。
      </p>
    </>
  );
  return (
    <div className="app-shell">
      <aside className={`sidebar ${open ? "open" : ""}`}>
        <div className="brand">
          <div className="brand-mark">
            <GraduationCap size={20} />
          </div>
          <div>
            <strong>研途</strong>
            <span>学习工作台</span>
          </div>
          <button
            className="mobile-close icon-button"
            onClick={() => setOpen(false)}
            aria-label="关闭菜单"
          >
            <X />
          </button>
        </div>
        <nav aria-label="主导航">
          {nav.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === "/"}
              onClick={() => setOpen(false)}
            >
              <item.icon size={18} />
              <span>{item.label}</span>
              {location.pathname === item.to && (
                <ChevronRight className="nav-arrow" size={15} />
              )}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="exam-card">
            <span>目标院校</span>
            <strong>{data.profile.target_school}</strong>
            <small>初试 {data.profile.exam_date} / 408统考</small>
          </div>
          <button
            className="sync-status"
            onClick={() => setAuth(true)}
            title="查看云端连接和账号"
          >
            <Cloud size={15} />
            <span>
              {syncStatusNames[syncStatus as SyncStatus] || syncStatus}
            </span>
            <span className={`status-dot ${syncStatus}`} />
          </button>
        </div>
      </aside>
      <div className="main-shell">
        <header className="topbar">
          <button
            className="menu-button icon-button"
            onClick={() => setOpen(true)}
            aria-label="打开菜单"
          >
            <Menu />
          </button>
          <div className="breadcrumb">
            {nav.find((n) => n.to === location.pathname)?.label || "研途"}
          </div>
          <div className="topbar-actions">
            {isDesktopRuntime() && <span className="storage-status" role="status">{storageStatusText}</span>}
            <span className="sync-pill">
              <span className={`status-dot ${syncStatus}`} />
              {syncStatusNames[syncStatus as SyncStatus] || syncStatus}
            </span>
            <button
              className="avatar"
              onClick={() => setAuth(true)}
              aria-label="账号与同步"
            >
              {data.profile.user_id === "local-demo" ? "D" : "U"}
            </button>
          </div>
        </header>
        <main>
          {(storageMessage || transferMessage) && (
            <div className="notice storage-notice" role={storageStatus === "error" ? "alert" : "status"}>
              <p>{transferMessage || storageMessage}</p>
              <div className="settings-actions">
                <button onClick={() => { void retryStorage().catch(() => {}); }}>
                  <RefreshCw size={16} />{storageBlocked ? "重新读取数据" : "重试保存"}
                </button>
                <button onClick={() => { if (isDesktopRuntime()) void importData(); else recoveryInputRef.current?.click(); }}><Upload size={16} />从 JSON 恢复</button>
                {!storageBlocked && <button onClick={() => { void exportData(); }}><Download size={16} />导出当前数据</button>}
                <input ref={recoveryInputRef} type="file" accept="application/json" hidden aria-label="选择恢复文件" onChange={(event) => { const file = event.target.files?.[0]; if (file) void importData(file); event.target.value = ""; }} />
              </div>
            </div>
          )}
          {storageBlocked ? <p role="alert">本地数据读取失败，已停止编辑和同步。请选择重新读取，或从 JSON 备份恢复。</p> : apiConfigured && apiUser && !apiOnboardingComplete ? <Onboarding /> : <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/calendar" element={<Calendar />} />
            <Route path="/tasks" element={<Tasks />} />
            <Route path="/progress" element={<Progress />} />
            <Route
              path="/settings"
              element={
                <SettingsPage
                  onAuth={() => setAuth(true)}
                  onExport={exportData}
                  onImport={importData}
                  setSettings={() => {}}
                />
              }
            />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>}
        </main>
      </div>
      {auth && (
        <Modal
          title={apiConfigured ? "服务器账号" : cloudConfigured ? "账号与云端同步" : "账号与同步"}
          onClose={() => {
            setAuth(false);
            setAuthError("");
          }}
        >
          {authContent}
        </Modal>
      )}
    </div>
  );
}

function SettingsPage({
  onAuth,
  onExport,
  onImport,
  setSettings,
}: {
  onAuth: () => void;
  onExport: () => void;
  onImport: (file?: File) => void;
  setSettings: (v: boolean) => void;
}) {
  const { data, setData, syncStatus, syncMessage, cloudConfigured, apiConfigured } = usePlanner();
  const [saved, setSaved] = useState(false);
  return (
    <>
      <div className="page-heading">
        <div>
          <h1>设置</h1>
          <p>调整计划边界，保持排程符合你的实际生活。</p>
        </div>
        <span className="sync-pill">
          <span className={`status-dot ${syncStatus}`} />
          {syncStatusNames[syncStatus as SyncStatus] || syncStatus}
        </span>
      </div>
      <div className="settings-grid">
        <section className="settings-section">
          <h2>备考信息</h2>
          <label>
            目标院校
            <input
              value={data.profile.target_school}
              onChange={(e) =>
                setData((d) => ({
                  ...d,
                  profile: { ...d.profile, target_school: e.target.value },
                }))
              }
            />
          </label>
          <label>
            目标方向
            <input
              value={data.profile.target_program}
              onChange={(e) =>
                setData((d) => ({
                  ...d,
                  profile: { ...d.profile, target_program: e.target.value },
                }))
              }
            />
          </label>
          <div className="form-grid">
            <label>
              初试第一天
              <input
                type="date"
                value={data.profile.exam_date}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: { ...d.profile, exam_date: e.target.value },
                  }))
                }
              />
            </label>
            <label>
              初试第二天
              <input
                type="date"
                value={data.profile.exam_end_date}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: { ...d.profile, exam_end_date: e.target.value },
                  }))
                }
              />
            </label>
          </div>
          <p className="muted">
            2027-12-25：政治、英语一　·　2027-12-26：数学一、408
          </p>
        </section>
        <section className="settings-section">
          <h2>排程边界</h2>
          <div className="form-grid">
            <label>
              每日学习上限（分钟）
              <input
                type="number"
                min={60}
                max={1440}
                step={30}
                value={data.profile.daily_limit_minutes}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: {
                      ...d.profile,
                      daily_limit_minutes: Number(e.target.value),
                    },
                  }))
                }
              />
            </label>
            <label>
              时间粒度（分钟）
              <select
                value={data.profile.granularity_minutes}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: {
                      ...d.profile,
                      granularity_minutes: Number(e.target.value),
                    },
                  }))
                }
              >
                <option value={30}>30</option>
                <option value={60}>60</option>
              </select>
            </label>
            <label>
              每日机动时间（分钟）
              <input
                type="number"
                min={30}
                max={180}
                step={30}
                value={data.profile.buffer_minutes}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: {
                      ...d.profile,
                      buffer_minutes: Number(e.target.value),
                    },
                  }))
                }
              />
            </label>
            <label>
              单科每日上限（分钟）
              <input
                type="number"
                min={60}
                max={480}
                step={30}
                value={data.profile.subject_limit_minutes}
                onChange={(e) =>
                  setData((d) => ({
                    ...d,
                    profile: {
                      ...d.profile,
                      subject_limit_minutes: Number(e.target.value),
                    },
                  }))
                }
              />
            </label>
          </div>
          <p className="muted">
            每天只安排事项和时长，不指定学习开始时间。固定课程、考试和休息可保留具体时间。
          </p>
        </section>
        <section className="settings-section">
          <h2>课程优先级</h2>
          <div className="subject-settings">
            {data.subjects.map((subject) => (
              <div key={subject.id}>
                <span className={`subject-label ${subject.id}`}>
                  <i />
                  {subject.name}
                </span>
                <select
                  value={subject.priority}
                  onChange={(e) =>
                    setData((d) => ({
                      ...d,
                      subjects: d.subjects.map((s) =>
                        s.id === subject.id
                          ? {
                              ...s,
                              priority: Number(e.target.value) as 1 | 2 | 3,
                            }
                          : s,
                      ),
                    }))
                  }
                >
                  <option value={3}>高</option>
                  <option value={2}>中高</option>
                  <option value={1}>普通</option>
                </select>
              </div>
            ))}
          </div>
          <p className="muted">政治计划从 2027 年 7 月开始逐步加入。</p>
        </section>
        <section className="settings-section">
          <h2>数据管理</h2>
          <div className="settings-actions">
            <button onClick={onExport}>
              <Download size={16} />
              导出本地数据
            </button>
            <label className="button-like" onClick={(event) => {
              if (isDesktopRuntime()) {
                event.preventDefault();
                void onImport();
              }
            }}>
              <Upload size={16} />
              恢复数据
              <input
                type="file"
                accept="application/json"
                hidden
                aria-label="恢复数据"
                onChange={(e) => {
                  if (e.target.files?.[0]) onImport(e.target.files[0]);
                  e.target.value = "";
                }}
              />
            </label>
            <button
              onClick={() => {
                setData(createInitialData(localDate()));
                setSaved(true);
              }}
            >
              <RefreshCw size={16} />
              恢复默认计划
            </button>
          </div>
          <p className="muted">
            导出文件包含事项、时间块、真实学习记录和重排快照。恢复默认计划会覆盖当前本地数据。
          </p>
        </section>
        <section className="settings-section connection">
          <h2>{apiConfigured ? "服务器连接" : "Supabase"}</h2>
          <div className="connection-row">
            <span
              className={`status-dot ${cloudConfigured ? "connected" : "demo"}`}
            />
            <div>
              <strong>
                {cloudConfigured
                  ? apiConfigured ? "已连接 Node API" : "已检测到 Supabase 配置"
                  : "未配置 Supabase 环境变量"}
              </strong>
              <p>
                {cloudConfigured
                  ? apiConfigured ? "登录后启用服务器保存、AI 规划和动态结算。" : "登录后启用多设备同步与 Realtime。"
                  : "本地 Demo 已完整可用；配置 .env 后重启开发服务器即可切换。配置项：VITE_SUPABASE_URL、VITE_SUPABASE_ANON_KEY。"}
              </p>
            </div>
            <button onClick={onAuth}>
              {cloudConfigured ? "账号登录" : "查看 Demo 状态"}
            </button>
          </div>
          {syncMessage && <p className="notice" role="status">{syncMessage}</p>}
        </section>
      </div>
      {saved && (
        <p className="notice" role="status">
          已恢复默认计划。
        </p>
      )}
    </>
  );
}

export default function App() {
  return (
    <PlannerProvider>
      <Shell />
    </PlannerProvider>
  );
}
