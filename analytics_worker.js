/**
 * TrailMate 匿名使用统计 —— Cloudflare Worker
 *
 * ── 它做什么 ─────────────────────────────────────────────
 * 接收 App 的心跳，按天记录"哪些安装标识今天活跃过"。
 * 只存 installId（App 自己生成的随机 UUID）+ 日期 + 版本。
 * 不含日记内容、照片、地名、坐标、手机号，也读不到 IMEI/AndroidID。
 *
 * ── 部署步骤（约 5 分钟）────────────────────────────────
 * 1. 注册 https://dash.cloudflare.com （免费）
 * 2. 左侧 Workers → Create → 新建一个 Worker，命名如 trailmate-ping
 * 3. 把本文件全部内容替换进去，Save & Deploy
 * 4. 在该 Worker 的 Settings → Variables and Dependencies → KV namespace
 *    点 Create 建一个 KV，namespace 绑定名必须是 **STATS**（区分大小写）
 * 5. 复制分配到的 URL，形如 https://trailmate-ping.<你的子域>.workers.dev
 * 6. 回到 Flutter：lib/services/analytics_service.dart 里
 *      static const String endpoint = 'https://trailmate-ping.xxx.workers.dev/ping';
 *    填上后重新打包，统计即生效（留空则整个功能自动停用，不发请求也不报错）
 *
 * ── 怎么查数据 ───────────────────────────────────────────
 *   GET  /                       总览：总装机数、今日 DAU、最近 14 天曲线
 *   GET  /days                   所有有记录的日期列表
 *   GET  /day?d=2026-10-13       某天活跃明细（数量 + id 前缀）
 *
 *   curl https://trailmate-ping.xxx.workers.dev/
 */

const DAY_TTL = 60 * 60 * 24 * 400; // 每条日记录保留 400 天
const INDEX_KEY = '__index__';

/**
 * ★★ 发新版时只需要改这里 ★★★
 *
 * latest : 最新版本号，必须与 App 里 app_constants.dart 的 appVersion 格式一致（如 1.0.1）
 * url    : 蓝奏云分享页地址（用户点"去下载"后跳到这里）
 * notes  : 更新说明，会原样显示在弹窗里；用 \n 换行
 * force  : true 则不给"以后再说"按钮。只在旧版有严重问题时才用
 *
 * 改完记得回到 Worker 页面点 Save and Deploy，否则不生效。
 */
const VERSION_INFO = {
  latest: '1.0.1',
  url: 'https://wwatw.lanzoub.com/iXhmW4c33y2j',
  notes: '修复精灵对话输入框残留问题；移除语音输入功能；新增检查更新。',
  force: false,
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 浏览器直接访问也能看，方便你随手开一下
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };

    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });

    // 版本接口不依赖 KV，放在 STATS 检查之前 —— 否则没绑 KV 时连版本号都读不到。
    try {
      if (url.pathname === '/version') {
        return json(VERSION_INFO, 200, cors);
      }
    } catch (e) {
      return json({ error: String(e && e.message ? e.message : e) }, 500, cors);
    }

    if (!env.STATS) {
      return json({ error: 'KV namespace "STATS" 未绑定' }, 500, cors);
    }

    try {
      if (url.pathname === '/ping' && request.method === 'POST') {
        return await handlePing(request, env, cors);
      }
      if (url.pathname === '/day') {
        return await handleDay(url, env, cors);
      }
      if (url.pathname === '/days') {
        return await handleDays(env, cors);
      }
      if (url.pathname === '/') {
        return await handleSummary(env, cors);
      }
      return json({ error: 'not found' }, 404, cors);
    } catch (e) {
      // 统计服务出错绝不能影响调用方；这里 500 会被 App 静默忽略
      return json({ error: String(e && e.message ? e.message : e) }, 500, cors);
    }
  },
};

async function handlePing(request, env, cors) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ ok: false, reason: 'bad json' }, 400, cors);
  }

  const day = String(body.day || '');
  const id = String(body.installId || '');
  const version = String(body.version || '')
    .slice(0, 32)
    .replace(/[^\w.\-+]/g, '');

  // 严格校验：格式不对的一律不收，避免 KV 被垃圾键污染
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    return json({ ok: false, reason: 'bad day' }, 400, cors);
  }
  if (!/^[0-9a-f]{8,64}$/i.test(id)) {
    return json({ ok: false, reason: 'bad installId' }, 400, cors);
  }

  const key = `d:${day}`;
  const set = await readSet(env, key);
  const isNew = !set.has(id);
  set.add(id);

  await env.STATS.put(key, JSON.stringify([...set]), { expirationTtl: DAY_TTL });

  // 维护一份"出现过哪些天"的索引，供总览快速枚举
  if (isNew) {
    const idx = new Set(((await env.STATS.get(INDEX_KEY)) || '').split(',').filter(Boolean));
    if (!idx.has(day)) {
      idx.add(day);
      const sorted = [...idx].sort().slice(-500); // 只留最近 500 天
      await env.STATS.put(INDEX_KEY, sorted.join(','), { expirationTtl: DAY_TTL });
    }
  }

  // 首次见到这个 id 才记入总装机集合（按周分片，避开单键无限增长）
  await maybeRecordGlobal(env, id, day);

  return json({ ok: true, firstToday: isNew }, 200, cors);
}

/** 总装机数：用 installId 前两位分 256 个桶，避免一个键存几万个 id。 */
async function maybeRecordGlobal(env, id, day) {
  const bucket = `g:${id.slice(0, 2).toLowerCase()}`;
  const cur = await env.STATS.get(bucket);
  const arr = cur ? JSON.parse(cur) : [];
  if (arr.includes(id)) return;
  arr.push(id);
  await env.STATS.put(bucket, JSON.stringify(arr), { expirationTtl: DAY_TTL });
}

async function handleDay(url, env, cors) {
  const day = url.searchParams.get('d');
  if (!day || !/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    return json({ error: '用法 /day?d=2026-10-13' }, 400, cors);
  }
  const set = await readSet(env, `d:${day}`);
  return json(
    {
      day,
      dau: set.size,
      // 只回显前缀，完整 id 不外泄
      ids: [...set].slice(0, 200).map((x) => x.slice(0, 8)),
    },
    200,
    cors,
  );
}

async function handleDays(env, cors) {
  const idx = ((await env.STATS.get(INDEX_KEY)) || '').split(',').filter(Boolean).sort();
  const out = [];
  for (const day of idx.slice(-120)) {
    const set = await readSet(env, `d:${day}`);
    out.push({ day, dau: set.size });
  }
  return json(out, 200, cors);
}

async function handleSummary(env, cors) {
  const idx = ((await env.STATS.get(INDEX_KEY)) || '').split(',').filter(Boolean).sort();
  const recent = idx.slice(-14);

  const series = [];
  for (const day of recent) {
    const set = await readSet(env, `d:${day}`);
    series.push({ day, dau: set.size });
  }

  // 总装机：汇总 256 个桶
  let installs = 0;
  for (let i = 0; i < 256; i++) {
    const b = i.toString(16).padStart(2, '0');
    const v = await env.STATS.get(`g:${b}`);
    if (v) installs += JSON.parse(v).length;
  }

  // 近 7 / 30 天去重活跃 = WAU / MAU
  const wau = await uniqueInDays(env, idx.slice(-7));
  const mau = await uniqueInDays(env, idx.slice(-30));

  // 客户端上报的是各设备本地日期，服务端再按 UTC 算"今天"会错位
  // （北京时间 08:00 前 UTC 仍是前一天），导致 todayDAU 莫名显示 0。
  // 因此直接取最近有记录的那一天作为"今日活跃"。
  const latest = series.length ? series[series.length - 1] : null;
  const activeToday = latest ? latest.dau : 0;

  return json(
    {
      app: 'TrailMate',
      generatedAt: new Date().toISOString(),
      totalInstalls: installs,
      todayDAU: activeToday,
      latestRecordedDay: latest ? latest.day : null,
      week7Active: wau,
      month30Active: mau,
      daysRecorded: idx.length,
      last14Days: series,
      note: 'installId 为各设备自行生成的随机 UUID，卸载重装即更换；无法据此识别个人。',
    },
    200,
    cors,
  );
}

async function uniqueInDays(env, days) {
  const all = new Set();
  for (const d of days) {
    const set = await readSet(env, `d:${d}`);
    for (const id of set) all.add(id);
  }
  return all.size;
}

async function readSet(env, key) {
  const raw = await env.STATS.get(key);
  if (!raw) return new Set();
  try {
    const arr = JSON.parse(raw);
    return new Set(Array.isArray(arr) ? arr : []);
  } catch {
    return new Set();
  }
}

function json(obj, status, extraHeaders) {
  return new Response(JSON.stringify(obj, null, 2), {
    status: status || 200,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...(extraHeaders || {}) },
  });
}
