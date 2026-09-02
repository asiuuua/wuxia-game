#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
由 docs/backlog.json 生成两份产物：
  1) docs/待办清单.md          —— 人读、可 git 跟踪的模块化待办清单
  2) docs/backlog_dashboard.html —— 自包含单文件看板（file:// 双击即开，无需服务器）
        含 隐性BUG / 未实现 / 是否占位 / 未来优化建议 四维度，按模块分页签展示。

用法：
  python tools/gen_backlog.py
纯标准库，无第三方依赖。

数据约定（docs/backlog.json）：
  - 每个 module 有 id/name/desc/items[]。
  - 每个 item：title/type/status( open|blocked|done )/placeholder/source/detail/suggestion。
  - 已完成项（status=done）可带 resolvedBy/resolvedAt/commit/resolution。
  - 可选 item.plain：{what,why,progress,missing,plan,bugs} 任意键覆盖自动合成的小白解读。
"""
import os
import json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_PATH = os.path.join(ROOT, "docs", "backlog.json")
MD_PATH = os.path.join(ROOT, "docs", "待办清单.md")
HTML_PATH = os.path.join(ROOT, "docs", "backlog_dashboard.html")

TYPE_ORDER = ["待办", "隐性BUG", "未实现", "占位", "优化建议"]
TYPE_COLOR = {
    "待办": "#60a5fa",
    "隐性BUG": "#f87171",
    "未实现": "#fbbf24",
    "占位": "#c084fc",
    "优化建议": "#34d399",
}
STATUS_LABEL = {"open": "未开始/进行中", "blocked": "受阻", "done": "已完成"}

# 小白解读「有什么用」按类型给默认话术
_WHY_DEFAULT = {
    "待办": "处理它能让对应系统更完善、少留隐患。",
    "隐性BUG": "这类问题最阴险：表面不报错，但实际行为不对，越早修越省事。",
    "未实现": "补上后这个功能才真正能用，否则只是空壳。",
    "占位": "替换掉临时占位，界面/体验才完整、才像正式作品。",
    "优化建议": "不阻塞流程，但做了能明显提升性能或手感。",
}
# 小白解读「还缺什么」按类型给默认话术
_MISSING_DEFAULT = {
    "待办": "待排期开始。",
    "隐性BUG": "还没合入修复补丁。",
    "未实现": "真实逻辑未落地。",
    "占位": "真实资源/真实逻辑未到位。",
    "优化建议": "待排期实施。",
}
# 小白解读「当前BUG」按类型给默认话术
_BUGS_DEFAULT = {
    "待办": "暂无已知代码BUG，属待办/优化项。",
    "隐性BUG": None,  # 特例：用 detail 拼
    "未实现": "功能已预留但未实现，调到会走空逻辑/降级。",
    "占位": "当前用占位实现（可能显示紫块/色块），不崩但非最终效果。",
    "优化建议": "暂无已知代码BUG，属待办/优化项。",
}


def load():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def auto_plain(it):
    """小白解读六问：自动由结构化字段合成，item.plain 任意键可覆盖。"""
    p = it.get("plain") or {}
    t = it.get("type", "")
    status = it.get("status", "open")
    detail = it.get("detail", "")
    suggestion = it.get("suggestion", "")
    source = it.get("source", "")

    what = p.get("what") or (detail if detail else it.get("title", ""))
    why = p.get("why") or _WHY_DEFAULT.get(t, "完善项目的一部分。")

    if status == "done":
        progress = "已完成 ✅（解决说明见本模块「已完成执行」清单）"
    elif status == "blocked":
        progress = "受阻：当前卡在依赖/未拍板上（来源：%s）。" % source
    else:
        progress = "尚未开始 / 进行中，还没真正落地。"
    progress = p.get("progress") or progress

    missing = p.get("missing") or _MISSING_DEFAULT.get(t, "待明确。")

    plan = p.get("plan") or (suggestion if suggestion else "（待定，见建议/来源）")

    if t == "隐性BUG":
        bugs = p.get("bugs") or ("⚠ 这就是个隐性BUG：" + (detail if detail else "表面正常但行为异常。"))
    else:
        bugs = p.get("bugs") or _BUGS_DEFAULT.get(t, "暂无已知代码BUG，属待办/优化项。")

    return {
        "what": what, "why": why, "progress": progress,
        "missing": missing, "plan": plan, "bugs": bugs,
    }


def gen_markdown(data):
    lines = []
    lines.append("# 武侠江湖 · 模块化待办清单（Backlog）\n")
    lines.append("> 自动生成自 `docs/backlog.json`（数据源）。改数据请用 `tools/gen_backlog.py` 重新生成本文件与看板。\n")
    lines.append("> 维护：每完成一项，把对应条目 `status` 改为 `done` 并重新生成；新增缺口追加到 `docs/backlog.json` 对应模块。\n")
    lines.append("> 四维度：待办 / 隐性BUG（表面不报错但行为异常）/ 未实现（预留未落地）/ 占位（临时实现待替换）/ 优化建议。\n")
    lines.append("> 跨窗口隐患流转仍以 `tools/handoff.py` 为权威；本文是其「人读总览」。\n")
    # 总览
    total = sum(len(m["items"]) for m in data["modules"])
    done_total = sum(1 for m in data["modules"] for it in m["items"] if it.get("status") == "done")
    lines.append("## 总览（更新于 %s）" % data.get("updated", ""))
    lines.append("- 待办项总数：**%d**（其中已完成 **%d**）" % (total, done_total))
    by_type = {}
    for m in data["modules"]:
        for it in m["items"]:
            by_type[it["type"]] = by_type.get(it["type"], 0) + 1
    lines.append("- 按类型：" + " · ".join("%s %d" % (t, by_type.get(t, 0)) for t in TYPE_ORDER))
    lines.append("")
    # 模块
    for m in data["modules"]:
        lines.append("## %s" % m["name"])
        if m.get("desc"):
            lines.append("> %s\n" % m["desc"])
        todo = [it for it in m["items"] if it.get("status") != "done"]
        done = [it for it in m["items"] if it.get("status") == "done"]
        if todo:
            lines.append("### 🟡 待解决 / 进行中（%d）" % len(todo))
            for it in todo:
                lines.append(_item_md(it))
        if done:
            lines.append("### ✅ 已完成执行（%d）" % len(done))
            for it in done:
                lines.append(_done_md(it))
        if not todo and not done:
            lines.append("（暂无条目）")
        lines.append("")
    lines.append("## 近期已闭环（备查）")
    for t in [
        "主菜单按钮 `mouse_filter` 写反致点击失效 → `WuxiaMenuButton.tscn`（c638497）",
        "主菜单悬停音效替换为木质按钮音（63263e2）",
        "背包溢出订阅 Toast（37c9ca18f539）",
        "婚礼演出场景 WeddingScene.tscn 创建 + 接线（e4161ea60416）",
        "技能栏冷却 + HUD 订阅（9ffe590492e9）",
        "战斗界面技能/敌人图标接线（f11a954808c2）",
        "静默拦截 BUG 双闸门守卫 lint_mouse_filter.py + 信号接缝测试（f4e8906/efb5f30）",
    ]:
        lines.append("- %s" % t)
    return "\n".join(lines) + "\n"


def _item_md(it):
    ph = " · 占位" if it.get("placeholder") else ""
    L = []
    L.append("- [%s] **%s**（%s%s）" % (it["type"], it["title"], STATUS_LABEL.get(it["status"], it["status"]), ph))
    L.append("  - 来源：%s" % it.get("source", ""))
    pl = auto_plain(it)
    L.append("  - 📌 是干嘛的：%s" % pl["what"])
    L.append("  - 💡 有什么用：%s" % pl["why"])
    L.append("  - 🚦 执行到哪步：%s" % pl["progress"])
    L.append("  - 🧩 还缺什么：%s" % pl["missing"])
    L.append("  - 🛠 以后怎么解决：%s" % pl["plan"])
    L.append("  - 🐞 当前BUG：%s" % pl["bugs"])
    return "\n".join(L)


def _done_md(it):
    L = []
    L.append("- ✅ **%s**" % it["title"])
    L.append("  - 解决方：%s" % it.get("resolvedBy", "（未署名）"))
    L.append("  - 解决日期：%s" % it.get("resolvedAt", "（未记录）"))
    if it.get("commit"):
        L.append("  - 提交：%s" % it["commit"])
    if it.get("resolution"):
        L.append("  - 解决说明：%s" % it["resolution"])
    return "\n".join(L)


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>武侠江湖 · 模块待办清单</title>
<style>
  :root{
    --bg:#0f1119; --panel:#15182a; --panel2:#1b1f33; --line:#2a2f47;
    --txt:#e6e8f0; --muted:#9aa0b8; --accent:#7c9cff;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--txt);font:14px/1.6 system-ui,"Microsoft YaHei",sans-serif}
  header{padding:16px 18px;border-bottom:1px solid var(--line);background:var(--panel)}
  header h1{margin:0;font-size:18px}
  header .sub{color:var(--muted);font-size:12px;margin-top:4px}
  .summary{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}
  .chip{background:var(--panel2);border:1px solid var(--line);border-radius:999px;padding:3px 10px;font-size:12px;color:var(--muted)}
  nav{display:flex;gap:4px;background:var(--panel);padding:0 12px;border-bottom:1px solid var(--line);flex-wrap:wrap}
  nav button{background:transparent;border:none;color:var(--muted);padding:10px 14px;cursor:pointer;font-size:14px;border-bottom:2px solid transparent}
  nav button:hover{color:var(--txt)}
  nav button.active{color:var(--txt);border-bottom-color:var(--accent)}
  .filters{display:flex;flex-wrap:wrap;gap:6px;padding:10px 14px;border-bottom:1px solid var(--line);align-items:center}
  .filters .lbl{color:var(--muted);font-size:12px;margin-right:4px}
  .filters label{display:inline-flex;align-items:center;gap:5px;font-size:12px;cursor:pointer;user-select:none}
  .filters input{accent-color:var(--accent)}
  main{padding:16px 18px;max-width:1100px}
  .grp-title{font-size:15px;font-weight:700;margin:18px 0 10px;padding-left:10px;border-left:4px solid var(--accent)}
  .grp-title.done{color:#34d399;border-left-color:#34d399}
  .moddesc{color:var(--muted);font-size:13px;margin:0 0 8px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 14px;margin-bottom:12px}
  .card.done{background:#101b16;border-color:#1f3a2c}
  .card .top{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
  .card .title{font-size:15px;font-weight:600}
  .badge{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;font-weight:600}
  .pill{font-size:11px;padding:2px 8px;border-radius:999px;background:var(--panel2);border:1px solid var(--line);color:var(--muted)}
  .pill.blocked{color:#f87171;border-color:#f8717155}
  .pill.done{color:#34d399;border-color:#34d39955}
  .kv{margin-top:6px;font-size:13px}
  .kv .k{color:var(--muted)}
  .sug{margin-top:8px;font-size:13px;background:var(--panel2);border-left:3px solid var(--accent);padding:6px 10px;border-radius:4px}
  .plain{margin-top:10px;border-top:1px dashed var(--line);padding-top:8px}
  .plain .pl{font-size:13px;margin:4px 0;display:flex;gap:6px}
  .plain .pl b{color:var(--accent);flex:0 0 96px;font-weight:600}
  .plain .pl span{color:var(--txt)}
  .empty{color:var(--muted);padding:30px;text-align:center}
</style>
</head>
<body>
<header>
  <h1>武侠江湖 · 模块待办清单</h1>
  <div class="sub" id="sub"></div>
  <div class="summary" id="summary"></div>
</header>
<nav id="nav"></nav>
<div class="filters">
  <span class="lbl">筛选类型：</span>
  <span id="filters"></span>
</div>
<main id="main"></main>
<script>
const BACKLOG = __JSON__;
const TYPE_COLOR = __TYPECOLOR__;
const STATUS_LABEL = __STATUSLABEL__;
const TYPE_ORDER = __TYPEORDER__;

document.getElementById('sub').textContent = '更新于 ' + (BACKLOG.updated||'') + ' · 共 ' +
  BACKLOG.modules.reduce((a,m)=>a+m.items.length,0) + ' 项（已完成 ' +
  BACKLOG.modules.reduce((a,m)=>a+m.items.filter(x=>x.status==='done').length,0) + '）';
const byType = {};
BACKLOG.modules.forEach(m=>m.items.forEach(it=>{byType[it.type]=(byType[it.type]||0)+1;}));
document.getElementById('summary').innerHTML = TYPE_ORDER
  .filter(t=>byType[t])
  .map(t=>'<span class="chip" style="border-color:'+TYPE_COLOR[t]+'55;color:'+TYPE_COLOR[t]+'">'+t+' '+byType[t]+'</span>')
  .join('');

const active = new Set(TYPE_ORDER);
const filtersEl = document.getElementById('filters');
TYPE_ORDER.forEach(t=>{
  const lab = document.createElement('label');
  lab.innerHTML = '<input type="checkbox" checked data-t="'+t+'"> <span style="color:'+TYPE_COLOR[t]+'">'+t+'</span>';
  lab.querySelector('input').addEventListener('change', e=>{
    if(e.target.checked) active.add(t); else active.delete(t);
    render(current);
  });
  filtersEl.appendChild(lab);
});

let current = BACKLOG.modules[0].id;
const navEl = document.getElementById('nav');
BACKLOG.modules.forEach(m=>{
  const b = document.createElement('button');
  b.textContent = m.name;
  b.dataset.tab = m.id;
  if(m.id===current) b.classList.add('active');
  b.addEventListener('click', ()=>{
    current = m.id;
    [...navEl.children].forEach(c=>c.classList.toggle('active', c.dataset.tab===current));
    render(current);
  });
  navEl.appendChild(b);
});

function plainOf(it){
  // 与服务端 auto_plain 对齐的轻量合成（前端仅用于展示）
  const t = it.type||'';
  const whyDef = {'待办':'处理它能让对应系统更完善、少留隐患。','隐性BUG':'这类问题最阴险：表面不报错，但实际行为不对，越早修越省事。','未实现':'补上后这个功能才真正能用，否则只是空壳。','占位':'替换掉临时占位，界面/体验才完整、才像正式作品。','优化建议':'不阻塞流程，但做了能明显提升性能或手感。'};
  const missDef = {'待办':'待排期开始。','隐性BUG':'还没合入修复补丁。','未实现':'真实逻辑未落地。','占位':'真实资源/真实逻辑未到位。','优化建议':'待排期实施。'};
  let progress, bugs;
  if(it.status==='done') progress='已完成 ✅（见本模块「已完成执行」）';
  else if(it.status==='blocked') progress='受阻：当前卡在依赖/未拍板（来源：'+(it.source||'')+'）。';
  else progress='尚未开始 / 进行中，还没真正落地。';
  if(t==='隐性BUG') bugs='⚠ 这就是个隐性BUG：'+(it.detail||'表面正常但行为异常。');
  else if(t==='占位') bugs='当前用占位实现（可能显示紫块/色块），不崩但非最终效果。';
  else if(t==='未实现') bugs='功能已预留但未实现，调到会走空逻辑/降级。';
  else bugs='暂无已知代码BUG，属待办/优化项。';
  const p = it.plain||{};
  return {
    what: p.what || (it.detail||it.title||''),
    why: p.why || (whyDef[t]||'完善项目的一部分。'),
    progress: p.progress || progress,
    missing: p.missing || (missDef[t]||'待明确。'),
    plan: p.plan || (it.suggestion||'（待定，见建议/来源）'),
    bugs: p.bugs || bugs
  };
}

function render(id){
  const m = BACKLOG.modules.find(x=>x.id===id);
  const main = document.getElementById('main');
  if(!m){ main.innerHTML='<div class="empty">无数据</div>'; return; }
  let html = '<p class="moddesc">'+(m.desc||'')+'</p>';
  const todo = m.items.filter(it=>it.status!=='done' && active.has(it.type));
  const done = m.items.filter(it=>it.status==='done');
  if(todo.length){
    html += '<div class="grp-title">🟡 待解决 / 进行中（'+todo.length+'）</div>';
    todo.forEach(it=>{ html += cardHtml(it, false); });
  }
  if(done.length){
    html += '<div class="grp-title done">✅ 已完成执行（'+done.length+'）</div>';
    done.forEach(it=>{ html += cardHtml(it, true); });
  }
  if(!todo.length && !done.length) html += '<div class="empty">当前模块无条目</div>';
  main.innerHTML = html;
}

function cardHtml(it, isDone){
  const col = TYPE_COLOR[it.type]||'#888';
  const ph = it.placeholder ? ' <span class="pill">占位</span>' : '';
  const st = '<span class="pill '+(it.status==='blocked'?'blocked':(it.status==='done'?'done':''))+'">'+(STATUS_LABEL[it.status]||it.status)+'</span>';
  let h = '<div class="card'+(isDone?' done':'')+'"><div class="top">'
    + '<span class="title">'+esc(isDone?'✅ ':'')+esc(it.title)+'</span>';
  if(!isDone) h += '<span class="badge" style="color:'+col+';border-color:'+col+'55;background:'+col+'1a">'+esc(it.type)+'</span>';
  h += st + ph + '</div>';
  if(isDone){
    h += '<div class="kv"><span class="k">解决方：</span>'+esc(it.resolvedBy||'（未署名）')+'</div>';
    h += '<div class="kv"><span class="k">解决日期：</span>'+esc(it.resolvedAt||'（未记录）')+'</div>';
    if(it.commit) h += '<div class="kv"><span class="k">提交：</span>'+esc(it.commit)+'</div>';
    if(it.resolution) h += '<div class="sug">解决说明：'+esc(it.resolution)+'</div>';
  } else {
    h += '<div class="kv"><span class="k">来源：</span>'+esc(it.source||'')+'</div>';
    const pl = plainOf(it);
    h += '<div class="plain">'
      + plRow('📌 是干嘛的', pl.what)
      + plRow('💡 有什么用', pl.why)
      + plRow('🚦 执行到哪步', pl.progress)
      + plRow('🧩 还缺什么', pl.missing)
      + plRow('🛠 以后怎么解决', pl.plan)
      + plRow('🐞 当前BUG', pl.bugs)
      + '</div>';
  }
  h += '</div>';
  return h;
}
function plRow(k, v){ return '<div class="pl"><b>'+esc(k)+'</b><span>'+esc(v)+'</span></div>'; }
function esc(s){ return (s||'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
render(current);
</script>
</body>
</html>
"""


def gen_html(data):
    import json as _json
    html = HTML_TEMPLATE
    html = html.replace("__JSON__", _json.dumps(data, ensure_ascii=False))
    html = html.replace("__TYPECOLOR__", _json.dumps(TYPE_COLOR, ensure_ascii=False))
    html = html.replace("__STATUSLABEL__", _json.dumps(STATUS_LABEL, ensure_ascii=False))
    html = html.replace("__TYPEORDER__", _json.dumps(TYPE_ORDER, ensure_ascii=False))
    return html


def main():
    data = load()
    with open(MD_PATH, "w", encoding="utf-8") as f:
        f.write(gen_markdown(data))
    with open(HTML_PATH, "w", encoding="utf-8") as f:
        f.write(gen_html(data))
    total = sum(len(m["items"]) for m in data["modules"])
    done = sum(1 for m in data["modules"] for it in m["items"] if it.get("status") == "done")
    print("OK  模块数=%d 条目数=%d（已完成 %d）" % (len(data["modules"]), total, done))
    print("  -> %s" % MD_PATH)
    print("  -> %s" % HTML_PATH)


if __name__ == "__main__":
    main()
