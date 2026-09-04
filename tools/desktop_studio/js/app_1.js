const A = (m,p,b)=>fetch(p,{method:m,headers:{'Content-Type':'application/json'},body:b?JSON.stringify(b):undefined}).then(r=>r.json());
function show(id,msg,ok){const e=document.getElementById(id);e.textContent=msg;e.className='status '+(ok?'ok':'bad');}
async function stat(){
  const [s,v]=await Promise.all([A('GET','/api/settings'), A('GET','/api/tool_version')]);
  const ver='工具版本：'+(v.build_time||'?')+' · '+v.md5;
  document.getElementById('hstat').textContent='工程：'+s.project_root+' ｜ 保险模式：'+(s.safe_mode?'开':'关')+' ｜ 回收站保留 '+s.retention_days+' 天 ｜ '+ver;
}

// ===================== UI 皮肤定制（读 /api/ui_skin，写回同路由） =====================
function _hexToRgbArr(hex){
  hex=hex.replace('#','');
  if(hex.length===3) hex=hex.split('').map(c=>c+c).join('');
  const n=parseInt(hex,16);
  return [((n>>16)&255)/255,((n>>8)&255)/255,(n&255)/255,1];
}
function _rgbArrToHex(a){
  const c=v=>('0'+Math.round(Math.max(0,Math.min(1,v))*255).toString(16)).slice(-2);
  return '#'+c(a[0])+c(a[1])+c(a[2]);
}
async function uiSkinLoad(){
  let d;
  try{ d=await A('GET','/api/ui_skin'); }catch(e){ return; }
  if(d.confirm_dialog_layout){
    const L=d.confirm_dialog_layout;
    if(L.panel_width){cdW.value=L.panel_width;cdWVal.textContent=L.panel_width;}
    if(L.panel_height){cdH.value=L.panel_height;cdHVal.textContent=L.panel_height;}
  }
  if(d.theme){
    if(Array.isArray(d.theme.panel_bg)) thPanel.value=_rgbArrToHex(d.theme.panel_bg);
    if(Array.isArray(d.theme.panel_border)) thBorder.value=_rgbArrToHex(d.theme.panel_border);
    if(Array.isArray(d.theme.title_color)) thTitle.value=_rgbArrToHex(d.theme.title_color);
    if(Array.isArray(d.theme.content_color)) thContent.value=_rgbArrToHex(d.theme.content_color);
  }
  if(d.main_menu_vfx){
    const V=d.main_menu_vfx;
    vxLeaves.checked=!!V.enabled_leaves; vxLeavesN.value=V.leaves_amount||0; vxLeavesNV.textContent=V.leaves_amount||0;
    vxCloud.checked=!!V.enabled_cloud; vxCloudS.value=V.cloud_speed||30;
    vxWater.checked=!!V.enabled_water; vxWaterP.value=V.water_period||2.5;
    vxBoat.checked=!!V.enabled_boat; vxBoatS.value=V.boat_speed||20;
  }
}
async function vfxApply(){
  const data={
    enabled_leaves:vxLeaves.checked, leaves_amount:parseInt(vxLeavesN.value,10),
    enabled_cloud:vxCloud.checked, cloud_speed:parseFloat(vxCloudS.value),
    enabled_water:vxWater.checked, water_period:parseFloat(vxWaterP.value),
    enabled_boat:vxBoat.checked, boat_speed:parseFloat(vxBoatS.value)
  };
  const r=await A('POST','/api/ui_skin',{kind:'main_menu_vfx',data:data});
  show('vfxStatus',r.msg||(r.ok?'已保存':'失败'),r.ok);
}
async function vfxReset(){
  const defs=(await A('GET','/api/ui_skin'))._defaults.main_menu_vfx;
  const r=await A('POST','/api/ui_skin',{kind:'main_menu_vfx',data:defs});
  if(r.ok){ vxLeaves.checked=!!defs.enabled_leaves; vxLeavesN.value=defs.leaves_amount; vxLeavesNV.textContent=defs.leaves_amount; vxCloud.checked=!!defs.enabled_cloud; vxCloudS.value=defs.cloud_speed; vxWater.checked=!!defs.enabled_water; vxWaterP.value=defs.water_period; vxBoat.checked=!!defs.enabled_boat; vxBoatS.value=defs.boat_speed; }
  show('vfxStatus',r.msg||(r.ok?'已复原':'失败'),r.ok);
}
async function cdApply(){
  const data={panel_width:parseInt(cdW.value,10),panel_height:parseInt(cdH.value,10)};
  const r=await A('POST','/api/ui_skin',{kind:'confirm_dialog_layout',data:data});
  show('cdStatus',r.msg||(r.ok?'已保存':'失败'),r.ok);
}
async function cdReset(){
  const r=await A('POST','/api/ui_skin',{kind:'confirm_dialog_layout',data:{panel_width:440,panel_height:220}});
  if(r.ok){cdW.value=440;cdWVal.textContent=440;cdH.value=220;cdHVal.textContent=220;}
  show('cdStatus',r.msg||(r.ok?'已复原':'失败'),r.ok);
}
async function thApply(){
  const data={_doc:"UI 通用主题配色（工作室「UI 皮肤定制 → 主题配色」可改）。",
    panel_bg:_hexToRgbArr(thPanel.value),panel_border:_hexToRgbArr(thBorder.value),
    title_color:_hexToRgbArr(thTitle.value),content_color:_hexToRgbArr(thContent.value),
    accent:[0.55,0.78,0.45,1]};
  const r=await A('POST','/api/ui_skin',{kind:'theme',data:data});
  show('thStatus',r.msg||(r.ok?'已保存':'失败'),r.ok);
}
async function thReset(){
  const defs=(await A('GET','/api/ui_skin'))._defaults;
  const r=await A('POST','/api/ui_skin',{kind:'theme',data:defs.theme});
  if(r.ok){thPanel.value=_rgbArrToHex(defs.theme.panel_bg);thBorder.value=_rgbArrToHex(defs.theme.panel_border);thTitle.value=_rgbArrToHex(defs.theme.title_color);thContent.value=_rgbArrToHex(defs.theme.content_color);}
  show('thStatus',r.msg||(r.ok?'已复原':'失败'),r.ok);
}

window._npcCache=[]; window._prevId=''; window._loaded=null; window._lastRename=null;

// tabs
function toggleUiMenu(force){
  const root=document.querySelector('[data-uiroot="ui"]');
  const menu=document.getElementById('uiMenu');
  if(!root||!menu) return;
  const open=force===undefined?!root.classList.contains('open'):!!force;
  root.classList.toggle('open',open);
  menu.classList.toggle('open',open);
}
function closeUiMenu(){ toggleUiMenu(false); }

document.querySelectorAll('#nav button').forEach(b=>b.onclick=(e)=>{
  if(b.dataset.uiroot){ toggleUiMenu(); e.stopPropagation(); return; }
  if(!b.dataset.tab) return;
  document.querySelectorAll('#nav button').forEach(x=>x.classList.remove('active'));
  document.querySelectorAll('.dd-item').forEach(x=>x.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(x=>x.classList.remove('active'));
  b.classList.add('active');
  const uiRoot=document.querySelector('[data-uiroot="ui"]');
  if(uiRoot && b.closest('#uiMenu')) uiRoot.classList.add('active');
  document.getElementById('tab-'+b.dataset.tab).classList.add('active');
  uiModuleGuide(b.dataset.tab);
  closeUiMenu();
  if(b.dataset.tab==='cel')celLoad();
  if(b.dataset.tab==='trash')trashLoad();
  if(b.dataset.tab==='settings')setLoad();
  if(b.dataset.tab==='log')logLoad();
  if(b.dataset.tab==='login')loginLoad();
  if(b.dataset.tab==='login')mmLoad();
  if(b.dataset.tab==='battle'){blLoadList();dpLoad();}
  if(b.dataset.tab==='loading')loadingLoad();
  if(b.dataset.tab==='uiart')uiArtLoad();
  if(b.dataset.tab==='uiskin')uiSkinLoad();
  if(b.dataset.tab==='hud')hudLoad();
  if(b.dataset.tab==='settings_screen')settingsScreenLoad();
  if(b.dataset.tab==='saveload_screen')saveloadScreenLoad();
  if(b.dataset.tab==='exp')expLoad();
  // 双闸门已并入「系统运维」页签，触发改为按钮手动（gateRun）；原 gate tab 分发不再需要
  if(b.dataset.tab==='orchestrate')orcLoad();
  if(b.dataset.tab==='coord'){backlogLoad();loadStartupCard();_initCoordRail();}
  if(b.dataset.tab==='handoff'){handoffLoad();}
  if(b.dataset.tab==='story')storyLoad();
  if(b.dataset.tab==='help')helpRender();
  if(b.dataset.tab==='sys'){logLoad();setLoad();trashLoad();i18nLoad();}
});

// ========== UI 模块统一引导：每模块「小白引导三行」+ 全局「统一三步流」 ==========
// 仅前端、不改游戏；未建模块在导航里标「即将上线」，此处只覆盖已落地模块。
const UI_GUIDE = {
  login:        {t:'登录界面', w:'改登录页的背景图与水墨氛围。', u:'让进游戏第一眼更有武侠味。', h:'选「背景图替换」→ 上传 png → 点保存即生效。'},
  loading:      {t:'预加载界面', w:'改读条界面的背景与文案。', u:'加载等待时更有代入感。', h:'同「背景图替换」入口 → 上传 → 保存。'},
  settings_screen:{t:'设置弹窗', w:'改设置弹窗面板的大小与位置。', u:'按钮/文字不再被挡、更顺手。', h:'UI 模块→设置弹窗 → 拖数值/点保存。'},
  saveload_screen:{t:'读档弹窗', w:'改读档卡片列的宽度与单卡大小。', u:'存档列表更宽松、好看。', h:'UI 模块→读档弹窗 → 拖数值/点保存。'},
  uiart:        {t:'UI 贴图', w:'换图标、按钮图等界面贴图。', u:'界面风格随美术资产更新。', h:'UI 模块→UI 贴图 → 上传 png → 保存。'},
  uiskin:       {t:'UI 皮肤定制', w:'改主题配色（颜色 token）。', u:'整体色调一键统一。', h:'UI 模块→UI 皮肤定制 → 选色/滑块 → 保存。'},
  hud:          {t:'HUD 布局', w:'改四块常驻面板的位置与大小。', u:'打斗/探索时信息更顺眼。', h:'UI 模块→HUD 布局 → 拖面板/拖角缩放 → 保存。'},
};
const UI_TABS = Object.keys(UI_GUIDE);
let _stepflowEl = null;
function ensureStepFlow(){
  if(_stepflowEl) return _stepflowEl;
  _stepflowEl = document.createElement('div');
  _stepflowEl.className = 'stepflow';
  _stepflowEl.innerHTML = '<b>统一三步流：</b> ① 选目标（哪个界面/元素） → ② 改参数/传图（滑块·上传） → ③ 预览并应用 ｜ 每个模块右下角都有「复原默认」一键回出厂值，零恐惧。';
  const main = document.querySelector('main');
  if(main) main.appendChild(_stepflowEl);
  return _stepflowEl;
}
function uiModuleGuide(tab){
  const isUI = UI_TABS.indexOf(tab) >= 0;
  const sf = ensureStepFlow();
  sf.style.display = isUI ? 'block' : 'none';
  // 先清掉所有 UI 模块里可能残留的引导块，避免重复
  UI_TABS.forEach(k=>{
    const sec = document.getElementById('tab-'+k);
    if(!sec) return;
    const old = sec.querySelector('.guide3');
    if(old) old.remove();
  });
  if(!isUI) return;
  const sec = document.getElementById('tab-'+tab);
  if(!sec) return;
  const g = UI_GUIDE[tab];
  const d = document.createElement('div');
  d.className = 'guide3';
  d.innerHTML = '<div class="g-title">🧭 '+g.t+' · 小白引导</div>'+
    '<div><b>这是干嘛的：</b>'+g.w+'</div>'+
    '<div><b>改了有啥用：</b>'+g.u+'</div>'+
    '<div><b>怎么改：</b>'+g.h+'</div>';
  sec.insertBefore(d, sec.firstChild);
}
uiModuleGuide('npc'); // 初始非 UI 模块，确保底栏隐藏、状态一致

document.addEventListener('click',e=>{
  const wrap=document.querySelector('.nav-dropdown-wrap');
  if(wrap && !wrap.contains(e.target)) closeUiMenu();
});

// ===================== UI 贴图（贴图直写 .tscn；位置/大小交给 Godot 拖拽） =====================
let UA_SCREENS=[]; let UA_CUR=null; let UA_KEYS=[]; let UA_PICK=-1;
async function uiArtLoad(){
  let r; try{ r=await A('GET','/api/ui_screens'); }catch(e){ show('uaStat','扫描失败：'+e,false); return; }
  UA_SCREENS=r.screens||[];
  if(!UA_CUR||!UA_SCREENS.some(s=>s.screen===UA_CUR)) UA_CUR=UA_SCREENS.length?UA_SCREENS[0].screen:null;
  uaRenderList(); uaRenderSlots();
  show('uaStat', (r.msg||'')+'（共 '+UA_SCREENS.length+' 个界面）', !!r.ok);
}
function uaRenderList(){
  const kw=(document.getElementById('uaSearch').value||'').trim().toLowerCase();
  const box=document.getElementById('uaList');
  const arr=UA_SCREENS.filter(s=>!kw||s.title.toLowerCase().includes(kw)||s.screen.toLowerCase().includes(kw));
  box.innerHTML = arr.length? arr.map(s=>{
    const has=s.slots.filter(x=>x.has_texture).length;
    return `<div class="item ${s.screen===UA_CUR?'sel':''}" onclick="uaPick(${UA_SCREENS.indexOf(s)})">
      <b>${s.title}</b><small>${s.slots.length} 个槽位${has?' · '+has+' 张已绑':''}</small></div>`;
  }).join('') : '<div class="item"><small>无匹配界面</small></div>';
}
function uaPick(i){ UA_CUR=UA_SCREENS[i].screen; uaRenderList(); uaRenderSlots(); }
function uaRenderSlots(){
  const s=UA_SCREENS.find(x=>x.screen===UA_CUR);
  const box=document.getElementById('uaSlots');
  if(!s){ document.getElementById('uaTitle').textContent=''; box.innerHTML=''; UA_KEYS=[]; return; }
  document.getElementById('uaTitle').textContent = s.title+'  —  '+s.screen;
  UA_KEYS=s.slots.map(sl=>sl.key);
  box.innerHTML = s.slots.length? s.slots.map((sl,i)=>{
    const prev = sl.has_texture
      ? `<img src="/api/ui_slot/file?key=${encodeURIComponent(sl.key)}&t=${Date.now()}" style="width:100%;height:108px;object-fit:contain;background:#0c0e16;border-radius:6px;border:1px solid var(--line)">`
      : `<div style="width:100%;height:108px;display:flex;align-items:center;justify-content:center;background:#0c0e16;border:1px dashed var(--line);border-radius:6px;color:var(--muted);font-size:12px">空槽位 · 未绑图</div>`;
    return `<div style="background:var(--panel2);border:1px solid var(--line);border-radius:8px;padding:10px">
      ${prev}
      <div style="margin-top:8px;font-size:12px;word-break:break-all"><b>${sl.node}</b></div>
      <div style="color:var(--muted);font-size:11px">${sl.type} · ${sl.prop}</div>
      <div class="btns" style="margin-top:8px">
        <button class="act" onclick="uaUpload(${i})">⏫ 传图</button>
        ${sl.has_texture?`<button class="act bad" onclick="uaClear(${i})">清除</button>`:''}
      </div></div>`;
  }).join('') : '<div class="hint">该界面没有贴图槽位。点上方「＋ 给该界面加背景图槽位」新增一个，再上传图片。</div>';
}
function uaUpload(i){ UA_PICK=i; const f=document.getElementById('uaFile'); f.value=''; f.click(); }
function uaReadB64(f){return new Promise((res,rej)=>{const fr=new FileReader();fr.onload=()=>res(String(fr.result).split(',')[1]||'');fr.onerror=rej;fr.readAsDataURL(f);});}
async function uaFileChosen(inp){
  const f=inp.files&&inp.files[0]; if(!f||UA_PICK<0) return;
  const key=UA_KEYS[UA_PICK]; if(!key) return;
  const [screen,node,prop]=key.split('|');
  show('uaStat','上传中…',true);
  const b64=await uaReadB64(f);
  const r=await A('POST','/api/ui_slot/upload',{screen:screen,node:node,prop:prop,data:b64});
  show('uaStat', r.msg||(r.ok?'完成':'失败'), !!r.ok);
  if(r.ok) await uiArtLoad();
}
async function uaClear(i){
  const key=UA_KEYS[i]; if(!key) return;
  const [screen,node,prop]=key.split('|');
  const r=await A('POST','/api/ui_slot/clear',{screen:screen,node:node,prop:prop});
  show('uaStat', r.msg||(r.ok?'已清除':'失败'), !!r.ok);
  if(r.ok) await uiArtLoad();
}
async function uaAddBg(){
  if(!UA_CUR) return;
  const r=await A('POST','/api/ui_bg/add',{screen:UA_CUR});
  show('uaStat', r.msg||(r.ok?'已新增':'失败'), !!r.ok);
  if(r.ok) await uiArtLoad();
}

// ---------- NPC ----------
async function npcLoad(){
  const list=await A('GET','/api/npc');
  window._npcCache=list;
  renderNpcListEl();
  npcRefRender();
  drawMap();
  npcRegionPop(list);
}
const _REGION_NAME={newbie_village:'新手村 newbie_village',misty_town:'迷烟镇 misty_town'};
function npcRegionPop(list){
  const sel=document.getElementById('n_region'); if(!sel)return;
  const keep=sel.value;
  const cur=window._loaded&&window._loaded.id?window._loaded.region:'';
  const seen=new Set((list||[]).map(n=>n.region).filter(Boolean).concat(['newbie_village']));
  sel.innerHTML='';
  [...seen].sort().forEach(r=>{
    const o=document.createElement('option');o.value=r;o.textContent=_REGION_NAME[r]||r;sel.appendChild(o);
  });
  if(cur&&seen.has(cur))sel.value=cur;
  else if(seen.has('newbie_village'))sel.value='newbie_village';
  else sel.value=keep||'';
}
function renderNpcListEl(){
  const el=document.getElementById('npcList'); if(!el)return;
  const q=String(document.getElementById('npcSearch')&&document.getElementById('npcSearch').value||'').trim().toLowerCase();
  const list=(window._npcCache||[]).filter(n=>!q||String(n.id||'').toLowerCase().includes(q)||String(n.name||'').toLowerCase().includes(q));
  el.innerHTML='';
  list.forEach(n=>{
    const d=document.createElement('div');d.className='item';
    const nm=document.createElement('span');nm.textContent=(n.name?n.name+' · ':'')+n.id;d.appendChild(nm);
    const rg=document.createElement('small');rg.textContent=_REGION_NAME[n.region]||n.region||'新手村';
    rg.style.marginLeft='6px';rg.style.opacity='.75';d.appendChild(rg);
    d.onclick=()=>npcSel(n);el.appendChild(d);
  });
  if(list.length===0)el.innerHTML='<div class="item">'+(q?'无匹配':'暂无 NPC')+'</div>';
}

// ---------- NPC 坐标参考栏（#44：唯一ID + 名称(空显 null) + 坐标；支持随机抽5 / 点列表显示该项） ----------
window._npcRefMode='all'; window._npcRefIds=null; window._npcRefSel='';
function npcRefList(){
  let list=(window._npcCache||[]).slice();
  if(window._npcRefMode==='pick'&&window._npcRefIds){const set=new Set(window._npcRefIds);list=list.filter(n=>set.has(n.id));}
  if(window._npcRefMode==='one'&&window._npcRefSel){list=list.filter(n=>n.id===window._npcRefSel);}
  return list;
}
function npcRefRender(){
  const ref=document.getElementById('npcRef');if(!ref)return;
  ref.innerHTML='';
  const list=npcRefList();
  if(list.length===0)ref.innerHTML='<span class="pill npc">（无匹配项）</span>';
  list.forEach(n=>{
    const nm=(n.name!==undefined&&n.name!==null&&String(n.name).trim()!=='')?String(n.name):'null';
    const c=document.createElement('span');c.className='chip'+(n.id===window._npcRefSel?' sel':'');
    c.innerHTML='<b>'+n.id+'</b> · '+nm+' · ('+(n.pos_x||0)+','+(n.pos_y||0)+')';
    c.title='点一下把 '+n.id+' 的坐标抄到表单';
    c.onclick=()=>{document.getElementById('n_px').value=n.pos_x||0;document.getElementById('n_py').value=n.pos_y||0;show('npcStat','已抄 '+n.id+' 的坐标 '+(n.pos_x||0)+','+(n.pos_y||0),true);drawMap();};
    ref.appendChild(c);
  });
  const info=document.getElementById('npcRefInfo');
  if(info)info.textContent='显示 '+list.length+' / 共 '+(window._npcCache||[]).length+' 项'
    +(window._npcRefMode==='pick'?'（随机抽样）':(window._npcRefMode==='one'?'（跟随左侧选择）':'（全部）'));
}
function npcRefAll(){window._npcRefMode='all';window._npcRefIds=null;window._npcRefSel='';npcRefRender();}
function npcRefRandom(){
  const pool=(window._npcCache||[]).slice();
  if(pool.length===0){show('npcStat','暂无 NPC 可抽',false);return;}
  for(let i=pool.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));const t=pool[i];pool[i]=pool[j];pool[j]=t;}
  window._npcRefMode='pick';window._npcRefIds=pool.slice(0,5).map(n=>n.id);window._npcRefSel='';
  npcRefRender();show('npcStat','已随机抽取 '+window._npcRefIds.length+' 个参考坐标',true);
}
function lockId(on){const idEl=document.getElementById('n_id');idEl.disabled=!on;
  document.getElementById('n_lock').style.display=on?'':'none';
  if(on)document.getElementById('n_rollback').style.display='none';}
function npcSel(n){
  window._loaded=JSON.parse(JSON.stringify(n));
  window._prevId=n.id; window._lastRename=null;
  // 坐标参考栏跟随左侧选择：只显示当前这一项
  window._npcRefMode='one'; window._npcRefSel=n.id; npcRefRender();
  document.getElementById('n_undorename').style.display='none';
  document.querySelectorAll('#npcList .item').forEach(x=>x.classList.remove('sel'));
  const idEl=document.getElementById('n_id');idEl.value=n.id; lockId(true);
  const rgSel=document.getElementById('n_region'); if(rgSel&&n.region)rgSel.value=n.region;
  document.getElementById('n_name').value=n.name||'';
  document.getElementById('n_px').value=n.pos_x||0;
  document.getElementById('n_py').value=n.pos_y||0;
  document.getElementById('n_sprite').value=n.sprite||'';
  document.getElementById('n_portrait').value=n.portrait||'';
  renderPortraitInfo(n);
  document.getElementById('n_dialog').value=n.dialog_id||'';
  document.getElementById('n_quest').value=n.quest_id||'';
  document.getElementById('n_battle').value=n.battle_id||'';
  drawMap();
  nsLoad(n.id);
}
function nsLoad(nid){
  A('GET','/api/npc_stats').then(stats=>{
    const e=(stats||{})[nid]||{};
    const list=(v,sep)=>Array.isArray(v)?v.join(sep||','):'' ;
    document.getElementById('ns_title').value=e.title||'';
    document.getElementById('ns_level').value=e.level!=null?e.level:'';
    document.getElementById('ns_attack').value=e.attack!=null?e.attack:'';
    document.getElementById('ns_defense').value=e.defense!=null?e.defense:'';
    document.getElementById('ns_hp').value=e.hp!=null?e.hp:'';
    document.getElementById('ns_spar').checked=!!e.can_spar;
    document.getElementById('ns_ma').value=list(e.martial_arts);
    document.getElementById('ns_gift').value=list(e.gift_prefs);
    document.getElementById('ns_pack').value=e.backpack_note||'';
  }).catch(()=>{});
}
async function nsSave(nid){
  const fields={title:document.getElementById('ns_title').value,
    level:document.getElementById('ns_level').value,attack:document.getElementById('ns_attack').value,
    defense:document.getElementById('ns_defense').value,hp:document.getElementById('ns_hp').value,
    can_spar:document.getElementById('ns_spar').checked,
    martial_arts:document.getElementById('ns_ma').value.split(',').map(s=>s.trim()).filter(s=>s),
    gift_prefs:document.getElementById('ns_gift').value.split(',').map(s=>s.trim()).filter(s=>s),
    backpack_note:document.getElementById('ns_pack').value};
  return await A('POST','/api/npc_stats',{npc_id:nid,fields});
}
function renderPortraitInfo(n){
  const ptype=document.getElementById('n_ptype');
  ptype.value=n.portrait_type||'static';
  const prev=document.getElementById('n_preview');prev.innerHTML='';
  const hb=n.half_body_portrait||'';
  if(!hb){
    prev.innerHTML='<span class="pill npc">当前：无立绘（游戏显示按 id 占位图）</span>';
    return;
  }
  const typeName={static:'静态图片',frame:'帧动画('+((n.portrait_frames||[]).length)+'帧)',spine:'Spine 骨骼'}[n.portrait_type||'static']||'静态图片';
  let html='<span class="pill npc">类型：'+typeName+'</span> ';
  if(n.portrait_type!=='frame'&&n.portrait_type!=='spine'){
    const pv='/api/npc/half_body/file?res='+encodeURIComponent(hb);
    html+='<img src="'+pv+'" onerror="this.onerror=null;this.style.display=\'none\';this.insertAdjacentHTML(\'afterend\',\'<code style=font-size:12px>'+ste(hb)+'</code>\')" style="height:90px;border:1px solid var(--line);border-radius:6px;vertical-align:middle">';
  }else{
    html+='<code style="font-size:12px">'+hb+(n.portrait_skeleton?' （骨骼：'+n.portrait_skeleton+'）':'')+'</code>';
  }
  prev.innerHTML=html;
}
async function npAssetPick(kind){
  // 立绘 sprite / 头像 portrait 的「选文件」：挑电脑里的图，上传后把 res:// 路径填进输入框
  const input=document.createElement('input');
  input.type='file';input.accept='.png,.webp,.jpg,.jpeg';
  input.onchange=async ()=>{
    const f=input.files && input.files[0];
    if(!f){return;}
    let b64;
    try{ b64=bToB64(await f.arrayBuffer()); }
    catch(e){ b64=''; }
    if(!b64){show('npcStat','读文件失败，图片可能过大',false);return;}
    const r=await A('POST','/api/npc/asset_upload',{filename:f.name,data:b64});
    show('npcStat',r.msg,r.ok);
    if(r.ok&&r.res){
      const el=document.getElementById(kind==='sprite'?'n_sprite':'n_portrait');
      if(el)el.value=r.res;
    }
  };
  input.click();
}
function bToB64(buf){
  // 大文件用分块转 base64，避免 String.fromCharCode(...大数组) 栈爆
  const bytes=new Uint8Array(buf);let s='';
  for(let i=0;i<bytes.length;i+=0x8000){s+=String.fromCharCode.apply(null,bytes.subarray(i,i+0x8000));}
  return btoa(s);
}
async function npcImportPortrait(){
  const nid=document.getElementById('n_id').value.trim();
  if(!nid){show('npcStat','请先填 NPC id（或选择已有 NPC）',false);return;}
  const f=document.getElementById('n_pfile');
  if(!f.files||f.files.length===0){show('npcStat','请先选择要导入的文件',false);return;}
  const ptype=document.getElementById('n_ptype').value;
  const file=await f.files[0].arrayBuffer();
  const b64=btoa(String.fromCharCode(...new Uint8Array(file)));
  const body={npc_id:nid,ptype:ptype,filename:f.files[0].name};
  if(ptype==='static')body.data=b64;else body.zip=b64;
  const r=await A('POST','/api/npc/portrait',body);
  show('npcStat',r.msg,r.ok);
  if(r.ok){await npcLoad();const sel=window._npcCache.find(x=>x.id===nid);if(sel)renderPortraitInfo(sel);}
}
async function npcClearPortrait(){
  const nid=document.getElementById('n_id').value.trim();
  if(!nid){show('npcStat','请先填 NPC id',false);return;}
  const r=await A('POST','/api/npc/portrait_clear',{npc_id:nid});
  show('npcStat',r.msg,r.ok);
  if(r.ok){await npcLoad();renderPortraitInfo({});}
}
function npcNew(){window._loaded=null;window._prevId='';window._lastRename=null;
  document.getElementById('n_undorename').style.display='none';
  ['n_id','n_name','n_sprite','n_portrait','n_dialog','n_quest','n_battle'].forEach(i=>document.getElementById(i).value='');
  const idEl=document.getElementById('n_id');idEl.disabled=false;idEl.value='';
  const rgSel=document.getElementById('n_region'); if(rgSel&&[...rgSel.options].some(o=>o.value==='newbie_village'))rgSel.value='newbie_village';
  document.getElementById('n_lock').style.display='none';
  document.getElementById('n_px').value=0;document.getElementById('n_py').value=0;
  renderPortraitInfo({});
  ['ns_title','ns_level','ns_attack','ns_defense','ns_hp','ns_ma','ns_gift','ns_pack'].forEach(i=>{const el=document.getElementById(i);if(el)el.value='';});
  const spar=document.getElementById('ns_spar');if(spar)spar.checked=false;
  drawMap();show('npcStat','新建模式：填好 id 和名称后点保存',true);}
function npcUnlockId(){
  const old=window._prevId||document.getElementById('n_id').value;
  if(!old)return;
  if(!confirm('⚠️ 修改「唯一ID」是危险操作：\n其它表（对话/任务/战斗/代码）里引用旧ID的地方不会自动更新，可能导致功能失效。\n确定要继续吗？'))return;
  if(!confirm('再次确认：要把唯一ID从【'+old+'】改成新值？\n旧记录会被移入回收站（可恢复）。'))return;
  const idEl=document.getElementById('n_id');idEl.disabled=false;
  document.getElementById('n_lock').style.display='none';
  document.getElementById('n_rollback').style.display='';
  show('npcStat','已解锁ID，修改后点保存即重命名（旧记录进回收站）',true);
}
function npcRollbackId(){
  const old=window._prevId||'';
  const idEl=document.getElementById('n_id');idEl.value=old;lockId(true);
  show('npcStat','已回退到原ID：'+old,true);
}
function npcRestore(){
  if(!window._loaded){show('npcStat','当前是新建模式，无需还原',true);return;}
  npcSel(window._loaded);show('npcStat','已还原本次改动',true);
}
async function npcUndoRename(){
  const r=window._lastRename;if(!r)return;
  const f={id:r.old,name:document.getElementById('n_name').value,
    pos_x:document.getElementById('n_px').value,pos_y:document.getElementById('n_py').value,
    sprite:document.getElementById('n_sprite').value,portrait:document.getElementById('n_portrait').value,
    dialog_id:document.getElementById('n_dialog').value,quest_id:document.getElementById('n_quest').value,
    battle_id:document.getElementById('n_battle').value};
  const res=await A('POST','/api/npc/rename',{old_id:r.new, ...f});
  show('npcStat',res.msg,res.ok);if(res.ok){window._lastRename=null;document.getElementById('n_undorename').style.display='none';await npcLoad();}
}
function refChange(kind,el){
  if(!window._loaded)return; // 新建模式不拦截
  const key=kind==='dialog'?'dialog_id':kind==='quest'?'quest_id':'battle_id';
  const snap=window._loaded[key]||'';
  if(el.value.trim()===snap)return;
  if(!confirm('你正在修改『'+kind+'ID』引用为【'+el.value+'】。\n确认吗？点取消可还原。')){
    el.value=snap;
  }
}
async function npcSave(){
  const idEl=document.getElementById('n_id');
  const newId=idEl.value.trim();
  if(!newId){show('npcStat','id 不能为空',false);return;}
  const f={id:newId,name:document.getElementById('n_name').value,
    pos_x:document.getElementById('n_px').value,pos_y:document.getElementById('n_py').value,
    sprite:document.getElementById('n_sprite').value,portrait:document.getElementById('n_portrait').value,
    dialog_id:document.getElementById('n_dialog').value,quest_id:document.getElementById('n_quest').value,
    battle_id:document.getElementById('n_battle').value,
    region:(document.getElementById('n_region')&&document.getElementById('n_region').value)||'newbie_village'};
  if(f.dialog_id){
    const dl=await A('GET','/api/dialog');
    if(!dl.includes(f.dialog_id)){
      if(!confirm('对话ID【'+f.dialog_id+'】在剧情对话表里找不到，保存后点该NPC可能没台词。仍要保存？'))return;
    }
  }
  let r;
  if(window._loaded && window._loaded.id!==newId){
    r=await A('POST','/api/npc/rename',{old_id:window._loaded.id, ...f});
  }else{
    r=await A('POST','/api/npc',f);
  }
  show('npcStat',r.msg,r.ok);
  if(r.ok){ if(window._loaded && window._loaded.id!==newId){window._lastRename={old:window._loaded.id,new:newId};document.getElementById('n_undorename').style.display='';}
    await nsSave(newId);
    await npcLoad(); }
}
async function npcDel(){
  const id=document.getElementById('n_id').value.trim();if(!id){show('npcStat','请先选择/新建一个 NPC',false);return;}
  if(!confirm('确定删除 '+id+'？（保险模式下会进回收站）'))return;
  const r=await A('DELETE','/api/npc/'+encodeURIComponent(id));show('npcStat',r.msg,r.ok);if(r.ok)npcLoad();
}

// 地图坐标预览
function drawMap(){
  const c=document.getElementById('mapCanvas');if(!c)return;
  const ctx=c.getContext('2d');const W=c.width,H=c.height;
  ctx.clearRect(0,0,W,H);
  ctx.strokeStyle='#2a2e44';ctx.lineWidth=1;
  for(let x=0;x<=W;x+=40){ctx.beginPath();ctx.moveTo(x,0);ctx.lineTo(x,H);ctx.stroke();}
  for(let y=0;y<=H;y+=40){ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(W,y);ctx.stroke();}
  const SX=W/820,SY=H/420;
  const curId=document.getElementById('n_id').value;
  window._npcCache.forEach(n=>{
    const x=(n.pos_x||0)*SX,y=(n.pos_y||0)*SY;
    ctx.beginPath();ctx.arc(x,y,6,0,7);
    ctx.fillStyle=(n.id===curId)?'#e6b35a':'#e66b6b';ctx.fill();
    ctx.fillStyle='#ccd2e6';ctx.font='11px sans-serif';ctx.fillText(n.id,x+9,y+3);
  });
}
document.getElementById('mapCanvas').addEventListener('click',e=>{
  const c=e.currentTarget;const rect=c.getBoundingClientRect();
  const scaleX=c.width/rect.width,scaleY=c.height/rect.height;
  const mx=(e.clientX-rect.left)*scaleX,my=(e.clientY-rect.top)*scaleY;
  const SX=c.width/820,SY=c.height/420;
  const px=Math.max(0,Math.round(mx/SX)),py=Math.max(0,Math.round(my/SY));
  document.getElementById('n_px').value=px;document.getElementById('n_py').value=py;
  drawMap();show('npcStat','已设置位置 ('+px+','+py+')，记得点「保存」',true);
});

// ---------- DIALOG ----------
let curDlg='';
async function dlgLoad(){
  const list=await A('GET','/api/dialog');const el=document.getElementById('dlgList');el.innerHTML='';
  list.forEach(id=>{const d=document.createElement('div');d.className='item';d.textContent=id;d.onclick=()=>dlgSel(id);el.appendChild(d);});
  if(list.length===0)el.innerHTML='<div class="item">（暂无对话）</div>';
  document.getElementById('lineList').innerHTML='';
  qgLoad();
}
async function dlgSel(id){
  curDlg=id;document.querySelectorAll('#dlgList .item').forEach(x=>x.classList.remove('sel'));
  event.target.classList.add('sel');
  const sh=await A('GET','/api/dialog/'+encodeURIComponent(id));const el=document.getElementById('lineList');el.innerHTML='';
  (sh.lines||[]).forEach(l=>{const d=document.createElement('div');d.className='item';d.textContent=l.id;d.onclick=()=>lineSel(l);el.appendChild(d);});
  if((sh.lines||[]).length===0)el.innerHTML='<div class="item">（暂无台词）</div>';
}
async function dlgCreate(){
  const id=document.getElementById('d_new').value.trim();if(!id){show('dlgStat','请输入新对话 id',false);return;}
  const r=await A('POST','/api/dialog',{action:'new',id});show('dlgStat',r.msg,r.ok);if(r.ok){document.getElementById('d_new').value='';dlgLoad();}
}
function lineSel(l){
  document.querySelectorAll('#lineList .item').forEach(x=>x.classList.remove('sel'));
  event.target.classList.add('sel');
  document.getElementById('l_id').value=l.id;document.getElementById('l_sid').value=l.speaker_id||'';
  document.getElementById('l_sname').value=l.speaker_name||'';document.getElementById('l_text').value=l.text||'';
  document.getElementById('l_next').value=l.next_id||'';document.getElementById('l_trig').value=(l.trigger_events||[]).join(',');
  optSet(l.options||[]);
}
function lineNew(){['l_id','l_sid','l_sname','l_text','l_next','l_trig'].forEach(i=>document.getElementById(i).value='');show('dlgStat','新建台词模式',true);optSet([]);}
function optSet(list){
  (window._curOpts=list.slice?list.slice():[]);
  const box=document.getElementById('optList');if(box)box.innerHTML='';
  (window._curOpts||[]).forEach(o=>box.appendChild(optRow(o)));
}
function optRow(o){
  o=o||{};
  const q=x=>String(x==null?'':x).replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;');
  const r=document.createElement('div');r.style.cssText='display:flex;gap:6px;align-items:center;flex-wrap:wrap;background:var(--panel2);padding:6px 8px;border-radius:6px;border:1px solid var(--line)';
  const kind=(o.cond&&o.cond.kind)||'';
  const arg=(o.cond&&o.cond.arg!=null)?o.cond.arg:'';
  r.innerHTML='<input class="op-t" style="flex:2;min-width:120px" placeholder="选项文本" value="'+q(o.text||'')+'">'
    +'<input class="op-j" style="flex:1;min-width:90px" placeholder="跳转台词id" value="'+q(o.jump_id||'')+'">'
    +'<select class="op-k" style="width:105px"><option value="">无条件</option>'
    +'<option value="favor"'+(kind==='favor'?' selected':'')+'>好感≥</option>'
    +'<option value="flag"'+(kind==='flag'?' selected':'')+'>flag 为真</option></select>'
    +'<input class="op-a" style="width:110px" placeholder="数值 / flag键" value="'+q(arg)+'">'
    +'<button class="act bad" type="button" onclick="this.parentNode.remove()">✕</button>';
  return r;
}
function optAdd(){const box=document.getElementById('optList');box.appendChild(optRow({}));}
function optCollect(){
  const box=document.getElementById('optList');if(!box)return [];
  return Array.from(box.children).map(r=>{
    const k=r.querySelector('.op-k').value, a=r.querySelector('.op-a').value;
    const out={text:r.querySelector('.op-t').value,jump_id:r.querySelector('.op-j').value};
    if(k&&String(a).trim()!=='')out.cond={kind:k,arg:(k==='favor')?Number(a):String(a).trim()};
    return out;
  }).filter(o=>o.text||o.jump_id);
}
async function lineSave(){
  if(!curDlg){show('dlgStat','请先选一个对话',false);return;}
  const line={id:document.getElementById('l_id').value.trim(),speaker_id:document.getElementById('l_sid').value,
    speaker_name:document.getElementById('l_sname').value,text:document.getElementById('l_text').value,
    next_id:document.getElementById('l_next').value,trigger_events:document.getElementById('l_trig').value.split(',').map(s=>s.trim()).filter(Boolean),
    options:optCollect()};
  if(!line.id){show('dlgStat','台词 id 不能为空',false);return;}
  const r=await A('POST','/api/dialog',{action:'upsert_line',dlg_id:curDlg,line});show('dlgStat',r.msg,r.ok);if(r.ok)dlgSel(curDlg);
}
async function lineDel(){
  if(!curDlg){show('dlgStat','请先选一个对话',false);return;}
  const lid=document.getElementById('l_id').value.trim();if(!lid){show('dlgStat','请先选一条台词',false);return;}
  if(!confirm('删除台词 '+lid+'？（保险模式下进回收站）'))return;
  const r=await A('POST','/api/dialog',{action:'delete_line',dlg_id:curDlg,line_id:lid});show('dlgStat',r.msg,r.ok);if(r.ok)dlgSel(curDlg);
}
async function dlgDel(){
  if(!curDlg){show('dlgStat','请先选一个对话',false);return;}
  if(!confirm('删除整个对话 '+curDlg+'？（保险模式下进回收站）'))return;
  const r=await A('POST','/api/dialog',{action:'delete_dialog',dlg_id:curDlg});show('dlgStat',r.msg,r.ok);if(r.ok){curDlg='';dlgLoad();}
}

// ---------- STORY DESIGN DESK (合并面板：选演员→写剧情→看走向/自测) ----------
let curStNpc=null;
window._stData={npc:[],npcStats:{},dialogs:[],quests:[]};
function ste(x){return String(x==null?'':x).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function stBadge(cls,t){return '<span class="sbadge '+cls+'">'+t+'</span>';}
async function storyLoad(){
  const st=document.getElementById('stStat'); if(!st)return; st.textContent='加载中…';
  try{
    const [npc,stats,dialogs,qg]=await Promise.all([
      A('GET','/api/npc'), A('GET','/api/npc_stats'), A('GET','/api/dialog'), A('GET','/api/quest_graph')]);
    window._stData={npc:npc||[], npcStats:stats||{}, dialogs:dialogs||[], quests:((qg&&qg.quests)||[])};
  }catch(e){ st.textContent='加载失败：'+e; return; }
  renderStNpcList();
  npcLoad();
  qgLoad();
  st.textContent='已加载 '+window._stData.npc.length+' 个演员（在②选一个开写台词）'; 
}
window._stNpcSearch='';
function stNpcSearchSet(v){ window._stNpcSearch=v||''; renderStNpcList(); }
function renderStNpcList(){
  const el=document.getElementById('stNpcList'); if(!el)return;
  const qs=window._stData.quests||[];
  const cats=stCatLoad();
  const sq=String(window._stNpcSearch||'').trim().toLowerCase();
  const hit=n=>!sq||String(n.id||'').toLowerCase().includes(sq)||String(n.name||'').toLowerCase().includes(sq);
  // 顶部分类条：新建分类 + 各分类小胶囊（都是拖放目标）；搜索框是上方静态元素，不随列表重建以免输入丢焦点
  let bar='<div style="margin-bottom:6px;display:flex;flex-wrap:wrap;gap:6px;align-items:center">'+
    '<button class="act sec" type="button" style="font-size:11px;padding:2px 9px;flex:none" onclick="stCatAdd()">➕ 新建分类</button>';
  Object.keys(cats).forEach(name=>{
    const n=(cats[name]||[]).length;
    bar+='<span class="st-cat" data-cat="'+ste(name)+'" title="把 NPC 拖到这个小胶囊上 = 放进「'+name+'」"><span>🗂 '+ste(name)+'</span>('+n+')'+
      '<i class="st-cat-del" data-del="'+ste(name)+'" title="删除这个分类">✖</i></span>';
  });
  bar+='<span class="muted" style="font-size:11px;width:100%">输入名称或 ID（如「村长」/「npc_village_chief」）会立刻过滤出匹配的演员；拖 NPC 到分类胶囊上可按区域归类，仅后台浏览不影响游戏。</span></div>';
  // 已分类的组 + 未分类（都吃搜索过滤）
  const used=[].concat.apply([],Object.keys(cats).map(k=>(cats[k]||[]).filter(Boolean)));
  const uncat=window._stData.npc.filter(n=>!used.includes(n.id));
  let html=bar;
  Object.keys(cats).forEach(name=>{
    const list=(cats[name]||[]).map(id=>window._stData.npc.find(n=>n.id===id)).filter(Boolean).filter(hit);
    if(list.length)html+=stCatGroupHtml('🗂 '+name,list,qs,true);
  });
  const u2=uncat.filter(hit);
  if(u2.length||Object.keys(cats).every(k=>(cats[k]||[]).filter(Boolean).filter(hit).length===0))html+=stCatGroupHtml('🗂 未分类',u2,qs,false);
  const matched=window._stData.npc.filter(hit);
  if(sq&&matched.length===0)html+='<div class="hint" style="padding:8px">没有名称或 ID 匹配「'+ste(sq)+'」的演员</div>';
  el.innerHTML=html;
  el.querySelectorAll('.sitem').forEach(item=>{
    item.draggable=true;
    item.addEventListener('dragstart',ev=>{ ev.dataTransfer.setData('text/plain',item.dataset.nid||''); item.classList.add('drag'); });
    item.addEventListener('dragend',()=>item.classList.remove('drag'));
    item.onclick=()=>stNpcSel(window._stData.npc.find(n=>n.id===item.dataset.nid));
  });
  const targets=el.querySelectorAll('.st-cat, .st-cat-hd');
  targets.forEach(t=>{
    t.addEventListener('dragover',ev=>{ ev.preventDefault(); t.classList.add('over'); });
    t.addEventListener('dragleave',()=>t.classList.remove('over'));
    t.addEventListener('drop',ev=>{
      ev.preventDefault(); t.classList.remove('over');
      const id=ev.dataTransfer.getData('text/plain');
      if(!id) return;
      const name=typeof t.dataset.cat!=='undefined'?t.dataset.cat:t.dataset.hd;
      stCatMove(id,name);
    });
  });
  el.querySelectorAll('.st-cat-del').forEach(x=>{
    x.addEventListener('click',ev=>{ ev.stopPropagation(); stCatDel(x.dataset.del); });
  });
}
function stCatGroupHtml(hd,list,qs,deletable){
  let g='<div class="st-cat-hd" data-hd="'+(deletable?hd.replace(/^🗂 /,''):'未分类')+'" title="把 NPC 拖到我这里加入该分类">'+hd+'（'+list.length+'）';
  if(deletable)g+='<i class="st-cat-del" data-del="'+ste(hd.replace(/^🗂 /,''))+'" title="删除这个分类" style="font-style:normal;color:#ef6a6a;margin-left:6px">✖</i>';
  g+='</div>';
  list.forEach(n=>{
    let b='';
    if(n.dialog_id) b+=stBadge('mid','💬有对话'); else b+=stBadge('off','✖无对话');
    if(n.quest_id){ const has=qs.find(x=>x.id===n.quest_id||x.name===n.quest_id); b+=has?stBadge('ok','🗺有剧情图'):stBadge('mid','🗺图未匹配:'+n.quest_id); }
    else b+=stBadge('off','✖未接任务');
    g+='<div class="sitem'+(curStNpc===n.id?' sel':'')+'" data-nid="'+n.id+'" title="拖到上方分类可归类｜点选编辑"><b>'+ste(n.name||'(无名)')+'</b><div>'+b+'</div><small>'+ste(n.id)+(n.battle_id?' · 战:'+ste(n.battle_id):'')+(typeof n.pos_x==='number'?' · ('+n.pos_x+','+n.pos_y+')':'')+'</small></div>';
  });
  return g;
}
function stCatLoad(){ try{ const c=JSON.parse(localStorage.getItem('st_npc_cats')||'{}'); return c&&typeof c==='object'?c:{}; }catch(e){ return {}; } }
function stCatSave(c){ try{ localStorage.setItem('st_npc_cats',JSON.stringify(c)); }catch(e){} }
function stCatAdd(){
  const name=(prompt('给这个分类起个名字，例如「镇上」「野外」「禁地」。它只是个后台文件夹，方便你按区域看人，不影响游戏。')||'').trim();
  if(!name) return;
  const c=stCatLoad(); c[name]=c[name]||[]; stCatSave(c); renderStNpcList();
}
function stCatDel(name){
  if(!confirm('删除分类「'+name+'」？只是删掉这个后台文件夹，不会删任何 NPC，里面的 NPC 会回到「未分类」。')) return;
  const c=stCatLoad(); delete c[name]; stCatSave(c); renderStNpcList();
}
function stCatMove(id,name){
  const c=stCatLoad();
  Object.keys(c).forEach(k=>{ c[k]=(c[k]||[]).filter(x=>x!==id); });
  if(name&&name!=='未分类'){ c[name]=c[name]||[]; if(!c[name].includes(id))c[name].push(id); }
  stCatSave(c); renderStNpcList();
}
async function stNpcSel(n){
  curStNpc=n.id; window._stCur=n; window._stCurDlg=n.dialog_id||null;
  renderStNpcList();
  document.getElementById('stDlgWrap').innerHTML='<div class="hint" style="padding:8px">加载这个演员的台词…</div>';
  await stDlgRender(n);
  stQRender(n);
}
async function stDlgRender(n, wantDid){
  const w=document.getElementById('stDlgWrap'); const all=window._stData.dialogs||[];
  let did=wantDid!=null?wantDid:((n&&n.dialog_id)||'');
  window._stCurDlg=did;
  const tb=document.createElement('div');
  tb.style.cssText='display:flex;gap:6px;align-items:center;flex-wrap:wrap;margin-bottom:8px;padding:8px;background:var(--panel2);border:1px solid var(--line);border-radius:8px';
  tb.innerHTML='<b style="font-size:12px">选对话</b>'+
    '<select id="stDlgSel" style="flex:1;min-width:120px">'+
    '<option value="">（无：②选演员自动带出 / 或下面新建）</option>'+
    all.map(d=>'<option value="'+ste(d)+'"'+(d===did?' selected':'')+'>'+ste(d)+'</option>').join('')+
    '</select>'+
    '<button class="act sec" type="button" onclick="stNewDlgMode()">＋ 新建对话</button>'+
    '<button class="act bad" type="button" onclick="stDelDlg()">🗑 删该对话</button>'+
    '<button class="act sec" type="button" onclick="stDlgRefresh()">↻ 刷新</button>';
  w.innerHTML='<div class="hint" style="margin:4px 2px 8px">③ 写这段剧情：先在这里选一个「对话」（或在②选演员自动带上他的对话），下面是台词编辑器（含触发事件、选项条件）。</div>';
  w.appendChild(tb);
  document.getElementById('stDlgSel').addEventListener('change',ev=>{ const v=ev.target.value; window._stCurDlg=v; stDlgRender(null,v); });
  const body=document.createElement('div'); body.id='stDlgBody'; w.appendChild(body);
  await stRenderDlgBody(body,did,n);
}
async function stRenderDlgBody(body,did,n){
  if(!did){ body.innerHTML='<div class="hint">还没选对话。点②选一个演员会自动带上他的对话；或点「＋ 新建对话」自己开一段。</div>'+
    '<div class="status" id="stStatDlg"></div>'+
    '<div class="story-line" style="margin-top:6px"><label>新对话 id（唯一）</label><input id="st_newId" placeholder="例如 dlg_chapter2"></div>'+
    '<button class="act sec" type="button" onclick="stDoCreateDlg()">＋ 建出来编辑</button>'; return; }
  body.innerHTML='<div class="status" id="stStatDlg"></div><div class="hint">编辑对话：<code>'+ste(did)+'</code></div>';
  let sh; try{ sh=await A('GET','/api/dialog/'+encodeURIComponent(did)); }catch(e){ body.insertAdjacentHTML('beforeend','<div class="hint">读取失败：该对话可能还没建台词。</div>'); return; }
  const lines=(sh&&sh.lines)||[];
  if(!lines.length){ body.insertAdjacentHTML('beforeend','<div class="hint">这个对话还没有台词，下面直接新增。</div>'); stWrapLine(body,{},lines,did); return; }
  const sel=document.createElement('select'); sel.style.cssText='width:100%;margin:6px 0';
  sel.innerHTML='<option value="">＋ 新增台词</option>'+lines.map(l=>'<option value="'+ste(l.id)+'">'+ste((l.speaker_name||l.speaker_id||l.id))+'：'+ste(String(l.text||'').slice(0,26))+'</option>').join('');
  body.appendChild(sel);
  sel.addEventListener('change',()=>{ const lid=sel.value; const l=lid?lines.find(x=>x.id===lid):{}; stWrapLine(body,l,lines,did); });
  stWrapLine(body,lines[0],lines,did);
}
function stNewDlgMode(){ window._stCurDlg=''; stDlgRender(null,''); }
async function stDoCreateDlg(){
  const id=document.getElementById('st_newId').value.trim(); const s=document.getElementById('stStatDlg');
  if(!id){ if(s){s.textContent='请先填对话 id';s.style.color='#ef6a6a';} return; }
  const r=await A('POST','/api/dialog',{action:'new',id});
  if(s){s.textContent=r.msg;s.style.color=r.ok?'var(--good,#34d399)':'#ef6a6a';}
  if(r.ok){ if(!window._stData.dialogs.includes(id)) window._stData.dialogs.push(id);
    const n=window._stCur; if(n && !n.dialog_id){ n.dialog_id=id; renderStNpcList(); }
    stDlgRender(window._stCur,id); }
}
async function stDelDlg(){
  const did=window._stCurDlg; if(!did) return;
  if(!confirm('删除整个对话 '+did+'？（保险模式下进回收站）')) return;
  const r=await A('POST','/api/dialog',{action:'delete_dialog',dlg_id:did});
  const s=document.getElementById('stStatDlg'); if(s){s.textContent=r.msg;s.style.color=r.ok?'var(--good,#34d399)':'#ef6a6a';}
  if(r.ok){ window._stData.dialogs=window._stData.dialogs.filter(x=>x!==did);
    const n=window._stCur; if(n && n.dialog_id===did){ n.dialog_id=''; renderStNpcList(); }
    stDlgRender(null,''); }
}
async function stDlgRefresh(){ try{ const dl=await A('GET','/api/dialog'); window._stData.dialogs=dl||[]; }catch(e){} stDlgRender(window._stCur, window._stCurDlg); }
function stWrapLine(w,l,lines,did){
  window._stCurLine=l.id||null;
  const old=document.getElementById('stLineEdit'); if(old) old.remove();
  const box=document.createElement('div'); box.id='stLineEdit';
  box.innerHTML=
    '<div class="story-line"><label>台词 id</label><input id="sl_id" value="'+ste(l.id||'')+'" placeholder="新台词需填id"></div>'+
    '<div class="story-line"><label>谁在说</label><input id="sl_sid" value="'+ste(l.speaker_id||(window._stCur?window._stCur.id:''))+'" placeholder="演员id，主角填 player"></div>'+
    '<div class="story-line"><label>显示名</label><input id="sl_sname" value="'+ste(l.speaker_name||'')+'"></div>'+
    '<div class="story-line" style="flex-direction:column;align-items:stretch"><label>这句话</label><textarea id="sl_text" rows="2" placeholder="台词内容">'+ste(l.text||'')+'</textarea></div>'+
    '<div class="story-line"><label>下一句id</label><input id="sl_next" value="'+ste(l.next_id||'')+'" placeholder="空=本段结束"></div>'+
    '<div class="story-line"><label>触发事件(逗号)</label><input id="sl_trig" value="'+ste((l.trigger_events||[]).join(','))+'" placeholder="空=无"></div>';
  w.appendChild(box);
  const optsBox=document.createElement('div'); optsBox.id='stOptList'; optsBox.className='story-opts';
  box.appendChild(optsBox);
  (window._slOpts=(l.options||[]).slice()).forEach(o=>stAddOptRow(optsBox,o));
  const addBtn=document.createElement('button'); addBtn.className='act sec'; addBtn.type='button'; addBtn.textContent='＋ 加选项（分支）';
  addBtn.onclick=()=>stAddOptRow(optsBox,{});
  box.appendChild(addBtn);
  const row=document.createElement('div'); row.className='story-line'; row.style.cssText='margin-top:6px';
  const save=document.createElement('button'); save.className='act'; save.type='button'; save.textContent='💾 保存这句';
  save.onclick=()=>stLineSave(did);
  row.appendChild(save);
  box.appendChild(row);
}
function stAddOptRow(box,o){
  o=o||{}; const kind=(o.cond&&o.cond.kind)||''; const arg=(o.cond&&o.cond.arg!=null)?o.cond.arg:'';
  const r=document.createElement('div'); r.className='opt-row';
  r.innerHTML='<input class="ot" placeholder="选项文本" value="'+ste(o.text||'')+'" style="flex:2">'+
    '<input class="oj" placeholder="跳去台词id" value="'+ste(o.jump_id||'')+'" style="flex:1">'+
    '<select class="ok" style="width:104px"><option value="">无条件</option><option value="favor"'+(kind==='favor'?' selected':'')+'>好感≥</option><option value="flag"'+(kind==='flag'?' selected':'')+'>flag真</option></select>'+
    '<input class="oa" placeholder="数值/flag键" value="'+ste(arg)+'" style="width:104px">'+
    '<button class="act bad" type="button">✕</button>';
  r.querySelector('.act').onclick=()=>r.remove();
  box.appendChild(r);
}
function stOptCollect(){
  const box=document.getElementById('stOptList'); if(!box) return [];
  return Array.from(box.querySelectorAll('.opt-row')).map(r=>{
    const ot=r.querySelector('.ot').value, oj=r.querySelector('.oj').value;
    const ok=r.querySelector('.ok').value, oa=r.querySelector('.oa').value.trim();
    const out={text:ot, jump_id:oj};
    if(ok && oa!=='') out.cond={kind:ok, arg:(ok==='favor')?Number(oa):oa};
    return out;
  }).filter(o=>o.text||o.jump_id);
}
function stG(id){ const e=document.getElementById(id); return e?e.value:''; }
async function stLineSave(did){
  const lid=stG('sl_id').trim();
  if(!lid){ const s=document.getElementById('stStatDlg'); if(s)s.textContent='台词 id 不能为空'; return; }
  const line={id:lid, speaker_id:stG('sl_sid'), speaker_name:stG('sl_sname'), text:stG('sl_text'), next_id:stG('sl_next'),
    trigger_events:(stG('sl_trig')||'').split(',').map(s=>s.trim()).filter(Boolean), options:stOptCollect()};
  const r=await A('POST','/api/dialog',{action:'upsert_line', dlg_id:did, line});
  const s=document.getElementById('stStatDlg'); if(s){s.textContent=r.msg; s.style.color=r.ok?'var(--good,#34d399)':'#ef6a6a';}
  if(r.ok) stDlgRender(window._stCur||{id:'',dialog_id:did});
}
async function stNewDlg(nid){
  const id=document.getElementById('st_newId').value.trim();
  const s=document.getElementById('stStat');
  if(!id){ if(s)s.textContent='请先填对话 id'; return; }
  const r=await A('POST','/api/dialog',{action:'new',id});
  if(s){s.textContent=r.msg; s.style.color=r.ok?'var(--good,#34d399)':'#ef6a6a';
    s.textContent+=r.ok?'，记住：请到「NPC 数据」页把该演员的「对话 id」填成 '+id+'':'';
  }
  if(r.ok){ const n=window._stData.npc.find(x=>x.id===nid); if(n){n.dialog_id=id;} renderStNpcList(); }
}
function stBattleNote(bid){ return '<div class="hint" style="margin-top:6px;color:#f0b036">连战斗：点他会出现「开始战斗」按钮 → 进战斗（<code>'+ste(bid)+'</code>）。打赢/打输目前<b>不会回写</b>任务进度（旧机制才回写）。</div>'; }
function stQRender(n){
  const w=document.getElementById('stQWrap'); const qs=window._stData.quests||[];
  const q=qs.find(x=>x.id===n.quest_id||x.name===n.quest_id);
  if(!q){ w.innerHTML='<div class="hint" style="padding:6px">这个演员的任务 id=<code>'+ste(n.quest_id||'(空)')+'</code>，在任务图文件里<b>没找到对应图</b>。当前点他：只有对话'+(n.battle_id?('，或按「开始战斗」打一场'):'')+'。</div>'+ (n.battle_id?stBattleNote(n.battle_id):''); return; }
  const steps=stTrace(q.start_node,q.nodes||{});
  let html='<div class="hint" style="margin-bottom:6px">任务「'+ste(q.name||q.id)+'」的走向预览（<code>'+ste(q.id)+'</code>）</div>'+stNodeSeq(steps);
  w.innerHTML=html;
}
function stOpText(op){ if(!op||typeof op!=='object') return ste(String(op==null?'':op));
  const k=op.op||'';
  if(k==='flag_set') return ste('flag:'+op.key+'='+JSON.stringify(op.value));
  if(k==='favor_add') return ste('好感+'+(op.target||'?')+'+'+op.value);
  return ste(k+(op.key?(':'+op.key):'')+(op.value!==undefined?('='+JSON.stringify(op.value)):'')); }
function stTrace(start,nodes){
  const steps=[]; const seen=new Set(); let cur=start; let guard=0;
  while(cur && !seen.has(cur) && guard++<40){ seen.add(cur); const node=nodes[cur]; if(!node) break;
    steps.push({id:cur,type:node.type||'',next:node.next||'',onWin:node.on_win_next||'',opts:Array.isArray(node.options)?node.options:[],cond:node.require||node.if||null,ops:Array.isArray(node.then)?node.then:[]});
    if(node.type==='end'){ cur=''; }
    else if(Array.isArray(node.options)&&node.options.length){ const f=node.options.find(o=>o&&(o.next||o.jump_id))||node.options[0]; cur=f?(f.next||f.jump_id||''):''; }
    else if(typeof node.on_win_next==='string'&&node.on_win_next){ cur=node.on_win_next; }
    else { cur=node.next||''; } }
  return steps;
}
function stNodeSeq(steps){
  const tc={start:'#34d399',dialog:'#7c9cff',choice:'#f0b036',battle:'#ef6a6a',give_item:'#b47cff',flag_set:'#36c5c5',flag_check:'#e879f9',goal:'#9ce08f',end:'#e2e8f0'};
  const desc={start:'入口',dialog:'对话',choice:'玩家选择',battle:'战斗',give_item:'发/收物品',flag_set:'记状态(好感/进度)',flag_check:'按条件分流',goal:'更新目标',end:'结局'};
  let html='';
  steps.forEach((s,i)=>{ const c=tc[s.type]||'#94a3b8';
    html+='<div class="story-node" style="border-left-color:'+c+'"><span class="n-type" style="background:'+c+'22;color:'+c+';border:1px solid '+c+'55">'+ste(s.type)+'</span><b>'+ste(s.id)+'</b> · '+(desc[s.type]||s.type);
    if(s.ops&&s.ops.length){ html+='<div class="story-opts" style="color:#b47cff">⚙ '+s.ops.map(op=>stOpText(op)).join('，')+'</div>'; }
    if(s.cond){ try{ html+='<div style="font-size:11px;color:#f0b036">条件：'+ste(JSON.stringify(s.cond))+'</div>'; }catch(e){} }
    if(s.opts.length){ html+='<div class="story-opts">'+s.opts.map(o=>'<div class="opt-row">➜ '+ste(o.text||o.text_key||'(选项)')+((o.show)?'<span class="mini">[条件:'+ste(o.show)+']</span>':'')+((o.next||o.jump_id)?'  → <code>'+ste((o.next||o.jump_id))+'</code>':'')+'</div>').join('')+'</div>'; }
    html+='</div>';
    if(i<steps.length-1){ const nxt=(s.type==='battle'&&s.onWin)?s.onWin:s.next; html+='<div class="story-arrow">↓ '+(s.type==='battle'?'打赢后 ':'')+'<code>'+ste(nxt||'…')+'</code></div>'; }
  });
  html+='<div class="hint" style="margin-top:8px;color:#ef6a6a">⚠️ 界面已保存任务图，但游戏侧尚未把流程图<b>接入剧情主流程</b>——现在画图存数据可以，进游戏触发战斗/发物品/记好感还没接（见「📖 使用说明」现状体检）。</div>';
  return html;
}
async function storyVerify(){
  const s=window._stData; const n=window._stCur;
  const out=document.getElementById('stQWrap');
  if(!n){ const st=document.getElementById('stStat'); if(st)st.textContent='先在①选一个演员再自测'; return; }
  const prob=[], okay=[];
  if(!n.dialog_id) prob.push('演员没「对话 id」，点他不会说话。');
  else if(!(s.dialogs||[]).includes(n.dialog_id)) prob.push('对话 id「'+n.dialog_id+'」在对话文件里还没建（有字段没台词）。');
  else { let sh=null; try{ sh=await A('GET','/api/dialog/'+encodeURIComponent(n.dialog_id)); }catch(e){ }
    const lines=(sh&&sh.lines)||[]; if(!lines.length) prob.push('对话「'+n.dialog_id+'」是空的。');
    else { const ids=lines.map(l=>l.id);
      lines.forEach(l=>{ if(l.next_id && !ids.includes(l.next_id)) prob.push('台词「'+l.id+'」的下一句「'+l.next_id+'」不存在，会被说断。');
        (l.options||[]).forEach(o=>{ if(o.jump_id && !ids.includes(o.jump_id)) prob.push('选项「'+o.text+'」跳去「'+o.jump_id+'」不存在。'); }); });
      if(!prob.length) okay.push('对话「'+n.dialog_id+'」主轴与跳转引用完整。'); } }
  const q=(s.quests||[]).find(x=>x.id===n.quest_id||x.name===n.quest_id);
  if(!n.quest_id) prob.push('演员没接任何任务。');
  else if(!q) prob.push('任务 id「'+n.quest_id+'」没在任务图文件里，游戏不会按流程图跑这段。');
  else { const nodes=q.nodes||{}; if(!nodes[q.start_node]) prob.push('任务图「'+q.id+'」起点「'+q.start_node+'」不存在。');
    else { let bad=0; Object.keys(nodes).forEach(k=>{ const nd=nodes[k]; if(!nd||typeof nd!=='object') return;
      ['next','on_win_next'].forEach(f=>{ const v=nd[f]; if(typeof v==='string'&&v&&String(v).toLowerCase()!=='null'&&!nodes[v]){prob.push('节点「'+k+'」的 '+f+' 指向不存在节点「'+v+'」');bad++;} });
      (nd.options||[]).forEach(o=>{ if(o.next&&!nodes[o.next]){prob.push('节点「'+k+'」选项跳去不存在节点「'+o.next+'」');bad++;} }); });
    if(!bad) okay.push('任务图「'+q.id+'」节点引用完整（仅数据层）。'); } }
  okay.push('⚠️ 数据层通过≠进游戏生效：流程图触发战斗/发物品/记好感仍未接入游戏主流程。');
  if(n.battle_id) okay.push('连战斗：点他会出「开始战斗」按钮可进入战斗，但胜负不会回写任务进度。');
  let html='<div style="margin-top:8px;padding:9px;background:var(--panel);border:1px solid var(--line);border-radius:8px"><b>🔍 自测「'+(n.name||n.id)+'」：</b>'+
    (prob.length?'<span style="color:#ef6a6a">发现 '+prob.length+' 处问题</span>':'<span style="color:#34d399">数据层基本完整</span>')+
    (prob.length?'<ul style="margin:6px 0;padding-left:18px">'+prob.map(p=>'<li style="color:#ef6a6a">'+ste(p)+'</li>').join('')+'</ul>':'')+
    (okay.length?'<ul style="margin:6px 0;padding-left:18px">'+okay.map(o=>'<li style="color:#34d399">'+ste(o)+'</li>').join('')+'</ul>':'')+'</div>';
  out.insertAdjacentHTML('beforeend',html);
  const st=document.getElementById('stStat'); if(st)st.textContent='自测完成';
}
(function(){ const go=()=>{ const st=document.getElementById('tab-story'); if(st&&st.classList.contains('active')){ storyLoad(); } }; if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',go); else setTimeout(go,150); })();
// ③ 写这段剧情：输入框聚焦=蓝 的事件委托兜底（不依赖 :focus 伪类，保证真实点击/输入时也生效）
(function(){
  const wrap=()=>document.getElementById('stDlgWrap');
  document.addEventListener('focusin',ev=>{ const w=wrap(); if(w&&w.contains(ev.target)&&ev.target.matches('input,textarea,select')) ev.target.classList.add('st-focus'); });
  document.addEventListener('focusout',ev=>{ if(ev.target.classList) ev.target.classList.remove('st-focus'); });
})();

// ---------- HELP (使用说明页) ----------
function helpRender(){
  // 折叠式使用说明：点标题展开/收起。每个功能都按「大白话 / 里面填什么 / 举例 / 一句话总结」写，纯新手可照做。
  const root=document.getElementById('helpRoot'); if(!root) return;
  const sec=[
    {t:'🧭 先看懂整体（剧情设计台 = 一个屏配一段剧情）', hd:'从上到下 ①~⑤，照着顺序走完就算配好',
      open:1, body:
      '<p class="pl">这个「剧情设计台」把以前分开的 <b>NPC数据</b>、<b>剧情对话</b>、<b>任务流程图</b> 全并到一个页面，从上到下 ①~⑤ 正好是一段剧情的制作顺序：先有人（①）、挑中人（②）、他会说话（③）、看走向（④）、把走向画成流程图（⑤）。</p>'+
      '<p class="pl"><b>一句话：每一步做完，点按钮保存，就存进游戏文件里了。</b>不会改到游戏代码，是纯配置。</p>'+
      '<p class="pl">下面是每个区块点开看的说明。不知道从哪开始，就按 ①→②→③→④→⑤ 一个个点开读。</p>'},
    {t:'① NPC 数据（演员编辑）＝管"人"的档案', hd:'造角色、改名、摆位置、长相、属性',
      body:
      '<h4><span class="help-tag t-what">大白话</span>这栏是干嘛的</h4>'+
      '<p class="pl">这是每个能出现在地图上、能被你点到说话的"人"的档案。要加新角色、改他站哪、长什么样、多强，都在这里。</p>'+
      '<h4><span class="help-tag t-what">里面填什么（几个关键框）</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0">'+
      '<li><b>id</b>＝这个角色的唯一编号，只能在游戏里出现一次，改它会牵连其它地方（慎重）。</li>'+
      '<li><b>名称</b>＝显示给玩家看的名字，比如"村口老乞丐"。</li>'+
      '<li><b>pos_x / pos_y</b>＝他站在地图上的横/纵坐标；也可以在下面地图里点一下自动填。</li>'+
      '<li><b>立绘 sprite / 头像 portrait / 半身立绘</b>＝角色用的图片。立绘/头像旁边有个「📁 选文件」按钮，点它挑电脑里的图就自动传好并填好路径；半身立绘用下面的「⏫ 导入」。</li>'+
      '<li><b>对话 id / 任务 id / 战斗 id</b>＝把"这段对话/任务/战斗"挂到这个人身上，点他才会触发。</li>'+
      '<li><b>🧾 详细资料</b>＝称号/等级/攻击/防御/气血/武学/送礼/背包，目前<b>仅后台展示</b>，还没进战斗数值。</li></ul>'+
      '<h4><span class="help-tag t-example">举例</span></h4>'+
      '<p class="pl">想让镇口站个"老乞丐"可以对话：id 填 <code>npc_wandering_beggar</code>，名称填 <code>老乞丐</code>，pos 在地图上点一个位置，最后点「保存」。</p>'+
      '<h4><span class="help-tag t-tip">提示</span></h4><p class="pl">平时只写剧情可以不动这栏；缺角色或要"配属性"才来这里。</p>'},
    {t:'② 选演员（NPC）＝挑现在要给谁写剧情', hd:'点谁，③④就切到谁',
      body:
      '<h4><span class="help-tag t-what">大白话</span></h4>'+
      '<p class="pl">从 ① 已经造好的演员里，挑一个开始配剧情。挑中后 ③ 自动带上他的对话、④ 显示他的走向。</p>'+
      '<h4><span class="help-tag t-what">怎么认条目上的小标签</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0">'+
      '<li><code class="help-tag">💬有对话</code>＝他已经挂了会说话的台词。</li>'+
      '<li><code class="help-tag">🗺有剧情图</code>＝他的任务 id 在流程文件里能找到图。</li>'+
      '<li><code class="help-tag">✖无对话 / 未接任务</code>＝还没配，点他不会说话。</li></ul>'+
      '<h4><span class="help-tag t-example">举例</span></h4><p class="pl">点「老乞丐」→ ③ 立刻变成他的台词编辑、④ 变成他的走向预览。</p>'+
      '<h4><span class="help-tag t-tip">提示</span></h4><p class="pl">这栏顶部还能建<b>分类夹</b>（比如"镇上/野外"）把角色归类，只是帮你快速浏览，不影响游戏。</p>'},
    {t:'③ 写这段剧情（剧情对话）＝写"人说的话 + 给你的选项"', hd:'选对话 → 写台词 → 存句',
      body:
      '<h4><span class="help-tag t-what">大白话</span></h4>'+
      '<p class="pl">写这个演员点开会说的话，以及给你(玩家)的选项。以前独立的「剧情对话」页已并到这里。</p>'+
      '<h4><span class="help-tag t-what">顶部「选对话」下拉框</span></h4>'+
      '<p class="pl">列出所有对话，可切换/新建/删除。在 ② 选了演员会自动带上他的对话。</p>'+
      '<h4><span class="help-tag t-what">每句台词填什么</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0">'+
      '<li><b>台词 id</b>＝这句的唯一编号。</li>'+
      '<li><b>谁在说</b>＝说话人 id（主角填 <code>player</code>）。</li>'+
      '<li><b>显示名 / 这句话</b>＝头顶显示的名字和说的话。</li>'+
      '<li><b>下一句 id</b>＝说完这句接哪句（空＝本段结束）。</li>'+
      '<li><b>触发事件(逗号)</b>＝这句触发什么事件，可留空。</li>'+
      '<li><b>＋ 加选项（分支）</b>＝给这句出多个选择项：填"选项文字"、跳去哪句，还可加条件（好感≥ / flag 为真）。</li></ul>'+
      '<h4><span class="help-tag t-example">举例</span></h4>'+
      '<p class="pl">一句"你想打听什么吗？"，加两个选项：选项1"镇上最近出了什么事？"（跳去 <code>l1</code>）、选项2"没事了"（跳 <code>l2</code> 或留空结束）。填完点「💾 保存这句」。</p>'+
      '<h4><span class="help-tag t-tip">提示</span></h4><p class="pl">选项的<b>好感≥/flag 条件现在保存不会丢</b>了。</p>'},
    {t:'④ 看走向 & 自测＝预览 + 一键检查有没有断', hd:'看见整段流程，红绿报问题',
      body:
      '<h4><span class="help-tag t-what">大白话</span></h4>'+
      '<p class="pl">自动预览这个演员绑定的任务走向（入口→对话→选择→…→结局），帮你"看见"整段怎么走；再一键自测有没有断。</p>'+
      '<h4><span class="help-tag t-what">点「🔍 自测当前」会查三件事</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0">'+
      '<li>有没有跳去一个<b>根本不存在的台词/节点</b>；</li>'+
      '<li>有没有<b>绑了对话 id 但文件里没建这段对话</b>；</li>'+
      '<li>任务图<b>起点/连线引用</b>是否完整。</li></ul>'+
      '<h4><span class="help-tag t-example">举例</span></h4><p class="pl">某句"下一句 id"填错了，自测会红字列出"台词 XX 的下一句 XX 不存在"。</p>'+
      '<h4><span class="help-tag t-tip">提示</span></h4><p class="pl">红字＝有问题要改；绿字＝数据层通过。但"绿字≠进游戏真跑通"，见最后一节现状。</p>'},
    {t:'⑤ 画路线图（任务流程图）＝把任务画成流程图', hd:'下拉选图 → 拖方块 → 连线 → 保存整图',
      body:
      '<h4><span class="help-tag t-what">大白话</span></h4>'+
      '<p class="pl">把整个任务画成一张像流程图的节点图。原「🗺 任务流程图」已搬到这里，④ 预览用的就是这张图。</p>'+
      '<h4><span class="help-tag t-what">怎么操作</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0">'+
      '<li>顶部<b>下拉框选一张任务图</b>；</li>'+
      '<li>画布上<b>拖动方块</b>调整布局；</li>'+
      '<li>点方块在右侧编辑它的 JSON（节点 id、往哪接）；</li>'+
      '<li>连线看 <code>next / on_win_next / on_lose_next / options[].jump_id</code> 的走向；</li>'+
      '<li>改完点「💾 保存整图」。</li></ul>'+
      '<h4><span class="help-tag t-what">常用节点类型</span></h4>'+
      '<p class="pl"><code>start</code>入口 · <code>dialog</code>对话 · <code>choice</code>玩家选择 · <code>battle</code>战斗 · <code>give_item</code>发/收物品 · <code>flag_set</code>记状态 · <code>flag_check</code>按条件分流 · <code>end</code>结局</p>'+
      '<h4><span class="help-tag t-example">举例</span></h4><p class="pl">"走进镇上"→ 一个 choice 让玩家选"打探/直接走"→ 打探进 dialog → 战一场(battle，打赢走 on_win_next) → end。保存前会拦截"指向不存在节点"的引用。</p>'+
      '<h4><span class="help-tag t-tip">提示</span></h4><p class="pl"><b>现在画了能存数据，但还没接进游戏主流程</b>（触发战斗/发物品/记好感还没接），见下一节。</p>'},
    {t:'⚙️ 现状体检：现在哪些真能用、哪些还没接好（2026-09-03 对照源码）', hd:'⚠️ 画路线图存了，进游戏还未生效',
      body:
      '<h4><span class="help-tag t-what">✅ 真能用（进游戏确实会跑）</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0"><li>NPC 摆到地图、点他能对话（id/名字/坐标/对话 id）。</li><li>对话主干按 next_id 一句句往下接。</li><li>对话选项的"好感≥/持物品/任务激活中"条件能过滤（不该显示的会藏）。</li><li>对话里点「开始战斗」能进真实战斗。</li></ul>'+
      '<h4><span class="help-tag t-what">⚠️ 只显示/部分真</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0"><li>NPC 属性(等级/攻击/气血/武学/送礼)只显示，<b>不进战斗数值、不进对话条件</b>。</li><li>战斗"胜负"不会回写任务进度。</li></ul>'+
      '<h4><span class="help-tag t-what">❌ 还没接好</span></h4>'+
      '<ul style="padding-left:20px;margin:4px 0"><li>任务流程图<b>没接进游戏主流程</b>：画完不会按图触发战斗/发物品/记好感。</li><li>对话文本是直写中文，<b>不走多语言表</b>，换语言还是中文。</li></ul>'+
      '<h4><span class="help-tag t-tip">给想往下做的人</span></h4><p class="pl">P0 在游戏主流程调用 QuestGraph.run() 并接上 dialog/battle/give_item/flag 的 handler；P0 让好感与 flag 能随存档读写；P1 让 NPC 属性真进战斗、对话走多语言。这些大多落在游戏工程侧，需按项目流程派单给对应窗口。</p>'}
  ];
  let html='<h2 style="margin:0 0 6px">📖 使用说明 · 剧情设计台</h2>'+
    '<p class="muted" style="margin:0 0 14px">给新手的保姆级说明。下面每一项都能<b>点标题展开/收起</b>。照着 ①→②→③→④→⑤ 走完，就算配好一段剧情。不用懂程序。</p>';
  sec.forEach(s=>{
    html+='<div class="help-card'+(s.open?' open':'')+'">'+
      '<div class="help-card-head" onclick="helpToggle(this)"><span class="hcaret">▸</span><span class="hf">'+s.t+'</span><span class="hd">'+s.hd+'</span></div>'+
      '<div class="help-card-body">'+s.body+'</div></div>';
  });
  root.innerHTML=html;
}
function helpToggle(h){ const c=h.parentNode; c.classList.toggle('open'); }
(function(){ const go=()=>{ const st=document.getElementById('tab-help'); if(st&&st.classList.contains('active')) helpRender(); }; if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',go); })();

// ---------- CELEBRATION ----------
async function celLoad(){
  const list=await A('GET','/api/celebration');const el=document.getElementById('celList');el.innerHTML='';
  list.forEach(id=>{const d=document.createElement('div');d.className='item';d.textContent=id;d.onclick=()=>celSel(id);el.appendChild(d);});
  if(list.length===0)el.innerHTML='<div class="item">（暂无欢庆配置）</div>';
}
async function celSel(id){
  document.querySelectorAll('#celList .item').forEach(x=>x.classList.remove('sel'));
  event.target.classList.add('sel');
  const e=await A('GET','/api/celebration/'+encodeURIComponent(id));const cg=e.cg||{},end=e.end||{};
  document.getElementById('c_mtype').value=cg.media_type||'none';
  document.getElementById('c_media').value=cg.media_path||'';document.getElementById('c_bgm').value=cg.bgm||'';
  document.getElementById('c_lines').value=(cg.lines||[]).join('\n');
  document.getElementById('c_end').value=(end.lines||[]).join('\n');
  window._cel=id;
}
function celBind(){const id=document.getElementById('c_new').value.trim();if(!id){show('celStat','请输入 NPC id',false);return;}celSelById(id);}
function celSelById(id){document.getElementById('c_new').value='';window._cel=id;
  ['c_mtype','c_media','c_bgm','c_lines','c_end'].forEach(i=>document.getElementById(i).value='');
  document.getElementById('c_mtype').value='none';show('celStat','已绑定新 NPC：'+id+'（点保存写入）',true);}
async function celSave(){
  const id=window._cel;if(!id){show('celStat','请先选择或绑定一个 NPC',false);return;}
  const entry={cg:{media_type:document.getElementById('c_mtype').value,media_path:document.getElementById('c_media').value,
    bgm:document.getElementById('c_bgm').value,lines:document.getElementById('c_lines').value.split('\n').map(s=>s.trim()).filter(Boolean)},
    end:{media_type:'none',media_path:'',lines:document.getElementById('c_end').value.split('\n').map(s=>s.trim()).filter(Boolean)}};
  const r=await A('POST','/api/celebration',{npc_id:id,entry});show('celStat',r.msg,r.ok);if(r.ok)celLoad();
}
async function celDel(){
  const id=window._cel;if(!id){show('celStat','请先选择或绑定一个 NPC',false);return;}
  if(!confirm('删除 '+id+' 的欢庆配置？（保险模式下进回收站）'))return;
  const r=await A('DELETE','/api/celebration/'+encodeURIComponent(id));show('celStat',r.msg,r.ok);if(r.ok){window._cel='';celLoad();}
}

// ---------- TRASH ----------
async function trashLoad(){
  const list=await A('GET','/api/trash');const b=document.getElementById('trashBody');b.innerHTML='';
  list.forEach(t=>{
    const tr=document.createElement('tr');
    const kind={npc:'NPC',dlg_line:'台词',celebration:'欢庆',dlg:'对话'}[t.kind]||t.kind;
    tr.innerHTML=`<td><span class="pill ${t.kind}">${kind}</span></td><td>${t.id}</td><td>${t.ts.replace('T',' ')}</td>`;
    const td=document.createElement('td');
    const rb=document.createElement('button');rb.className='act sec';rb.textContent='恢复';rb.onclick=async()=>{const r=await A('POST','/api/trash/restore',{file:t._file});show('trashStat',r.msg,r.ok);trashLoad();};
    const pb=document.createElement('button');pb.className='act bad';pb.textContent='彻底删除';pb.onclick=async()=>{if(confirm('彻底删除 '+t.id+'？不可恢复')){await A('POST','/api/trash/purge',{file:t._file});trashLoad();}};
    td.appendChild(rb);td.appendChild(pb);tr.appendChild(td);b.appendChild(tr);
  });
  if(list.length===0)b.innerHTML='<tr><td colspan="4" style="color:var(--muted)">（回收站为空）</td></tr>';
}
async function trashCleanup(){const r=await A('POST','/api/trash/cleanup',{});show('trashStat','已清空过期项：'+(r.cleaned||0),true);trashLoad();}

// ---------- SETTINGS ----------
async function setLoad(){const s=await A('GET','/api/settings');
  document.getElementById('s_root').value=s.project_root;document.getElementById('s_port').value=s.port;
  document.getElementById('s_days').value=s.retention_days;document.getElementById('s_safe').value=String(s.safe_mode);
  try{const p=await A('GET','/api/project_root');document.getElementById('s_detected').value=p.root||'(未识别)';}catch(e){document.getElementById('s_detected').value='(读取失败)';}}
async function saveSettings(){
  const s={project_root:document.getElementById('s_root').value.trim(),port:parseInt(document.getElementById('s_port').value)||8765,
    retention_days:parseInt(document.getElementById('s_days').value)||30,safe_mode:document.getElementById('s_safe').value==='true'};
  const r=await A('POST','/api/settings',s);show('setStat',r.ok?'已保存（路径等下次启动生效）':'保存失败',r.ok);if(r.ok)stat();
}
// 浏览器文件夹选择（Chromium/Edge 支持 showDirectoryPicker）
async function pickRoot(){
  try{
    const h=window.showDirectoryPicker?await window.showDirectoryPicker():null;
    if(h){const p=h.name?(''+h.name):''; /* 仅得目录名，需拼接_handle，改用手动路径更可靠 */}
  }catch(e){ /* 用户取消或无权限，忽略 */ }
  const v=prompt('请输入工程根目录路径（含 project.godot 的文件夹）：\n例如 D:/武侠游戏 或 E:/我的游戏','');
  if(v){document.getElementById('s_root').value=v.trim();checkRoot();}
}
async function checkRoot(){
  const v=document.getElementById('s_root').value.trim();
  const r=await A('POST','/api/project_root/check',{root:v});
  show('rootStat',r.ok?('✓ '+v+' 是有效工程'):('✗ '+r.msg),r.ok);
  return r.ok;
}
async function applyRoot(){
  const v=document.getElementById('s_root').value.trim();
  const chk=await checkRoot();
  if(!chk)return;
  const r=await A('POST','/api/project_root/set',{root:v});
  if(r.ok){
    show('rootStat','✓ 已切换工程到 '+r.root+'，立即生效（无需重启）',true);
    document.getElementById('s_detected').value=r.root;
    stat();
    show('setStat','工程目录已变更并立即生效',true);
  }else{
    show('rootStat','✗ 切换失败：'+(r.msg||'未知错误'),false);
  }
}

// ---------- LOGIN UI ----------
function bufToB64(buf){let bin='';const b=new Uint8Array(buf);const c=0x8000;for(let i=0;i<b.length;i+=c){bin+=String.fromCharCode.apply(null,b.subarray(i,i+c));}return btoa(bin);}
async function loginLoad(){
  const info=await A('GET','/api/login/bg');
  const img=document.getElementById('loginBgImg');
  if(info.exists){img.style.display='';img.src='/api/login/bg/file?t='+Date.now();}
  else{img.style.display='none';}
  const texts=await A('GET','/api/login/texts');
  const tb=document.querySelector('#loginTextTbl tbody');tb.innerHTML='';
  texts.forEach(t=>{
    const tr=document.createElement('tr');
    const q=s=>(s==null?'':String(s)).replace(/"/g,'&quot;');
    tr.innerHTML=`<td style="padding:4px;border-bottom:1px solid #333">${t.desc}</td>`+
      `<td style="padding:4px;border-bottom:1px solid #333"><code>${t.key}</code></td>`+
      `<td style="padding:4px;border-bottom:1px solid #333"><input data-k="${t.key}" data-c="zh_CN" value="${q(t.zh_CN)}" style="width:120px"></td>`+
      `<td style="padding:4px;border-bottom:1px solid #333"><input data-k="${t.key}" data-c="zh_TW" value="${q(t.zh_TW)}" style="width:120px"></td>`+
      `<td style="padding:4px;border-bottom:1px solid #333"><input data-k="${t.key}" data-c="en" value="${q(t.en)}" style="width:120px"></td>`+
      `<td style="padding:4px;border-bottom:1px solid #333">${t.target}</td>`;
    tb.appendChild(tr);
  });
  const v=await A('GET','/api/login/version');
  document.getElementById('loginVer').value=v.version||'';
  document.getElementById('loginVerNote').textContent=v.note||'';
  const list=await A('GET','/api/login/btn_bg');
  const bl=document.getElementById('loginBtnBgList');bl.innerHTML='';
  list.forEach(b=>{
    const div=document.createElement('div');div.className='row';div.style.alignItems='center';
    const hasImg=b.path && b.path!=='';
    const prev=hasImg?`<img src="/api/login/btn_bg/file?btn_id=${encodeURIComponent(b.key)}&t=${Date.now()}" style="height:42px;border:1px solid #444;border-radius:6px">`:`<span class="pill npc">默认（无图）</span>`;
    div.innerHTML=`<label style="flex:1">${b.desc}</label>${prev}<input type="file" data-btn="${b.key}" accept="image/*"><span id="btnbg_${b.key}" style="margin-left:8px"></span><button class="act sec" data-clear="${b.key}">清除(null)</button>`;
    bl.appendChild(div);
  });
  bl.querySelectorAll('input[data-btn]').forEach(inp=>inp.onchange=async()=>{
    const f=inp.files[0];if(!f)return;
    const d=await f.arrayBuffer();const b64=bufToB64(d);
    const r=await A('POST','/api/login/btn_bg',{btn_id:inp.dataset.btn,data:b64,name:f.name});
    document.getElementById('btnbg_'+inp.dataset.btn).textContent=r.ok?'已存':'失败';
    if(r.ok)loginLoad();
  });
  bl.querySelectorAll('button[data-clear]').forEach(btn=>btn.onclick=async()=>{
    if(!confirm('把【'+btn.dataset.clear+'】的按钮背景图清除为 null（回退默认）？'))return;
    const r=await A('POST','/api/login/btn_bg_clear',{btn_id:btn.dataset.clear});
    show('loginStat',r.msg,r.ok);if(r.ok)loginLoad();
  });
  await loginLayoutLoad();
  await loginClarityLoad();
  await variantLoad();
  await mmAssetsLoad();
}

// ---------- 登录背景布局（多设备实时预览） ----------
const LOGIN_PRESETS=[
  {sm:'keep_aspect_covered',label:'铺满裁切 Cover（推荐）'},
  {sm:'keep_aspect',label:'完整显示 Contain'},
  {sm:'scale',label:'拉伸填满 Stretch'},
  {sm:'tile',label:'平铺 Tile'},
  {sm:'keep_centered',label:'居中 Center'},
  {sm:'keep_aspect_centered',label:'等比居中'},
];
const LOGIN_DEVICES=[
  {n:'PC 16:9',r:'16/9'},
  {n:'带鱼屏 21:9',r:'21/9'},
  {n:'iPad 4:3',r:'4/3'},
  {n:'手机 19.5:9',r:'19.5/9'},
];
let loginLayoutState={stretch_mode:'keep_aspect_covered',scrim_alpha:0.55,edge_auto:true,leaves_enabled:true};
function loginBgUrl(){return '/api/login/bg/file?t='+Date.now();}
function smToFit(sm){
  if(sm==='keep_aspect_covered'||sm==='cover')return 'cover';
  if(sm==='keep_aspect'||sm==='keep_aspect_centered')return 'contain';
  if(sm==='scale'||sm==='stretch')return 'fill';
  if(sm==='keep_centered')return 'contain';
  return 'cover';
}
function renderLoginPresets(){
  const box=document.getElementById('loginLayoutPresets');box.innerHTML='';
  LOGIN_PRESETS.forEach(p=>{
    const b=document.createElement('button');
    b.textContent=p.label;
    b.style.padding='7px 10px';b.style.borderRadius='8px';
    b.style.border='1px solid '+(p.sm===loginLayoutState.stretch_mode?'#4a8':'#555');
    b.style.background=p.sm===loginLayoutState.stretch_mode?'#234':'transparent';
    b.style.color='#eee';b.style.cursor='pointer';
    b.onclick=()=>{loginLayoutState.stretch_mode=p.sm;renderLoginPresets();loginLayoutRender();};
    box.appendChild(b);
  });
}
function sampleEdge(url,cb){
  const im=new Image();
  im.onload=()=>{
    try{
      const c=document.createElement('canvas');c.width=32;c.height=32;
      const ctx=c.getContext('2d');ctx.drawImage(im,0,0,32,32);
      const dt=ctx.getImageData(0,0,32,1).data, db=ctx.getImageData(0,31,32,1).data;
      let r=0,g=0,b=0,rb=0,gb=0,bb=0;
      for(let i=0;i<32;i++){r+=dt[i*4];g+=dt[i*4+1];b+=dt[i*4+2];rb+=db[i*4];gb+=db[i*4+1];bb+=db[i*4+2];}
      cb('rgb('+(r/32|0)+','+(g/32|0)+','+(b/32|0)+')','rgb('+(rb/32|0)+','+(gb/32|0)+','+(bb/32|0)+')');
    }catch(e){cb('#444','#444');}
  };
  im.onerror=()=>cb('#444','#444');
  im.src=url;
}
function loginLayoutRender(){
  const box=document.getElementById('loginDevicePreview');box.innerHTML='';
  const url=loginBgUrl();
  const fit=smToFit(loginLayoutState.stretch_mode);
  const scrim=loginLayoutState.scrim_alpha;
  sampleEdge(url,(tc,bc)=>{
    LOGIN_DEVICES.forEach(d=>{
      const wrap=document.createElement('div');wrap.style.width='200px';
      const lab=document.createElement('div');lab.textContent=d.n;lab.style.fontSize='12px';lab.style.color='#aaa';lab.style.marginBottom='4px';
      const frame=document.createElement('div');
      frame.style.width='200px';frame.style.aspectRatio=d.r;
      frame.style.border='1px solid #555';frame.style.borderRadius='8px';
      frame.style.overflow='hidden';frame.style.position='relative';
      frame.style.background=loginLayoutState.edge_auto?('linear-gradient(to bottom,'+tc+','+bc+')'):'#444';
      if(loginLayoutState.stretch_mode==='tile'){
        frame.style.backgroundImage='url('+url+')';
        frame.style.backgroundRepeat='repeat';
        frame.style.backgroundSize='100px 100px';
      }else{
        const img=document.createElement('img');
        img.src=url;img.style.position='absolute';img.style.inset='0';
        img.style.width='100%';img.style.height='100%';img.style.objectFit=fit;
        frame.appendChild(img);
      }
      if(scrim>0){
        const scr=document.createElement('div');
        scr.style.position='absolute';scr.style.inset='0';scr.style.background='#000';scr.style.opacity=scrim;
        frame.appendChild(scr);
      }
      wrap.appendChild(lab);wrap.appendChild(frame);box.appendChild(wrap);
    });
  });
}
async function loginLayoutLoad(){
  try{const d=await A('GET','/api/login/bg_layout');
    loginLayoutState={stretch_mode:d.stretch_mode||'keep_aspect_covered',scrim_alpha:typeof d.scrim_alpha==='number'?d.scrim_alpha:0.55,edge_auto:!!d.edge_auto,leaves_enabled:!!d.leaves_enabled};
  }catch(e){}
  document.getElementById('loginScrim').value=Math.round(loginLayoutState.scrim_alpha*100);
  document.getElementById('loginScrimVal').textContent=Math.round(loginLayoutState.scrim_alpha*100);
  document.getElementById('loginEdgeAuto').checked=loginLayoutState.edge_auto;
  document.getElementById('loginLeaves').checked=loginLayoutState.leaves_enabled;
  renderLoginPresets();
  loginLayoutRender();
}
function loginLayoutSave(){
  loginLayoutState.scrim_alpha=(parseInt(document.getElementById('loginScrim').value,10)||55)/100;
  loginLayoutState.edge_auto=document.getElementById('loginEdgeAuto').checked;
  loginLayoutState.leaves_enabled=document.getElementById('loginLeaves').checked;
  A('POST','/api/login/bg_layout',loginLayoutState).then(r=>{
    show('loginLayoutStat',r&&r.msg?r.msg:(r&&r.ok?'已保存':'失败'),r&&r.ok);
    loginLayoutRender();
  });
}
document.getElementById('loginScrim').addEventListener('input',e=>{
  loginLayoutState.scrim_alpha=(parseInt(e.target.value,10)||0)/100;
  document.getElementById('loginScrimVal').textContent=e.target.value;
  loginLayoutRender();
});
document.getElementById('loginEdgeAuto').addEventListener('change',e=>{loginLayoutState.edge_auto=e.target.checked;loginLayoutRender();});
document.getElementById('loginLeaves').addEventListener('change',e=>{loginLayoutState.leaves_enabled=e.target.checked;});

async function loginBgReplace(){
  const f=document.getElementById('loginBgFile').files[0];
  if(!f){show('loginBgStat','请先选一张图片',false);return;}
  const d=await f.arrayBuffer();const b64=bufToB64(d);
  const r=await A('POST','/api/login/bg',{data:b64,name:f.name});
  show('loginBgStat',r.msg||(r.ok?'已替换':'失败'),r.ok);
  if(r.ok){const img=document.getElementById('loginBgImg');img.style.display='';img.src='/api/login/bg/file?t='+Date.now();loginLayoutRender();loginClarityLoad();}
}
async function loginTextsSave(){
  const inputs=document.querySelectorAll('#loginTextTbl input[data-k]');
  const map={};
  inputs.forEach(i=>{const k=i.dataset.k,c=i.dataset.c;if(!map[k])map[k]={key:k};map[k][c]=i.value;});
  const rows=Object.values(map);
  const r=await A('POST','/api/login/texts',{rows});
  show('loginTextStat',r.msg||(r.ok?'已保存':'失败'),r.ok);
}

// ---------- 清晰度诊断 + 多分辨率变体（任务 #47） ----------
function verdictClass(v){return v==='清晰'?'ok':(v==='轻微发虚'?'':'bad');}
async function loginClarityLoad(){
  const box=document.getElementById('clarityBox');if(!box)return;
  try{
    const d=await A('GET','/api/login/bg');
    if(!d||!d.exists){box.innerHTML='<span class="pill">未设置背景图</span>';return;}
    const rows=(d.targets||[]).map(t=>{
      const cls=t.verdict==='清晰'?'ok':(t.verdict==='轻微发虚'?'':'bad');
      return '<tr><td style="padding:2px 10px 2px 0">'+t.name+'（'+t.width+'×'+t.height+'）</td>'
        +'<td style="padding:2px 10px 2px 0">放大 <b>'+t.scale+'×</b></td>'
        +'<td style="padding:2px 10px 2px 0" class="status '+cls+'">'+t.verdict+'</td></tr>';
    }).join('');
    box.innerHTML='当前图：<b>'+(d.width||'?')+' × '+(d.height||'?')+'</b> 像素（'+(d.ext||'')+'，'
      +((d.size||0)/1048576).toFixed(2)+' MB）<table style="margin-top:4px">'+rows+'</table>';
  }catch(e){box.textContent='读取失败：'+e;}
}
async function variantLoad(){
  const tb=document.getElementById('variantTbl');if(!tb)return;
  tb.innerHTML='<tr><td colspan="5" class="hint">读取中…</td></tr>';
  try{
    const d=await A('GET','/api/login/bg_variants');
    const vs=(d&&d.variants)||[];
    if(vs.length===0){tb.innerHTML='<tr><td colspan="5" class="hint">还没配置变体，游戏当前用主图。</td></tr>';return;}
    tb.innerHTML=vs.map(v=>
      '<tr>'+
      '<td style="padding:4px"><b>'+v.min_width+'</b> px</td>'+
      '<td style="padding:4px;font-size:12px">'+(v.exists?'<code>'+v.path+'</code>':'<span class="status bad">文件缺失</span>')+'</td>'+
      '<td style="padding:4px">'+(v.width?v.width+'×'+v.height:'—')+'</td>'+
      '<td style="padding:4px">'+(v.size?(v.size/1048576).toFixed(2)+' MB':'—')+'</td>'+
      '<td style="padding:4px"><button class="act bad" onclick="variantRemove('+v.min_width+')">删除</button></td>'+
      '</tr>').join('');
  }catch(e){tb.innerHTML='<tr><td colspan="5" class="status bad">读取失败</td></tr>';}
}
async function variantUpload(){
  const tag=document.getElementById('varTag').value.trim();
  const mw=document.getElementById('varMinW').value;
  const f=document.getElementById('varFile').files[0];
  if(!f){show('variantStat','请先选一张图片',false);return;}
  if(!tag){show('variantStat','请填档位名（例如 2k）',false);return;}
  const d=await f.arrayBuffer();const b64=bufToB64(d);
  const r=await A('POST','/api/login/bg_variant',{tag:tag,min_width:mw,data:b64});
  show('variantStat',(r&&r.msg)?r.msg:(r.ok?'已保存':'失败'),!!(r&&r.ok));
  if(r&&r.ok){document.getElementById('varFile').value='';variantLoad();}
}
async function btnBgScanFix(){
  const r=await A('POST','/api/login/btn_bg_fix',{});
  show('btnBgFixStat',(r&&r.msg)?r.msg:(r.ok?'体检完成':'失败'),!!(r&&r.ok));
  if(r&&r.ok)loginLoad();
}
async function variantRemove(min_width){
  if(!confirm('删除「视口宽 ≥ '+min_width+'」这一档变体？游戏会回退到主图。'))return;
  const r=await A('POST','/api/login/bg_variant_remove',{min_width:min_width});
  show('variantStat',(r&&r.msg)?r.msg:(r.ok?'已删除':'失败'),!!(r&&r.ok));
  if(r&&r.ok)variantLoad();
}

// ---------- 预加载界面（自由拖拽可视化编辑） ----------
const LOAD_ELS=['progress_bar','progress_label','tip_label','version_label'];
const LOAD_DEF={progress_bar:{x:0.5,y:0.86,w:0.5,h:0.02,align:'center'},
                progress_label:{x:0.5,y:0.81,align:'center'},
                tip_label:{x:0.5,y:0.66,align:'center'},
                version_label:{x:0.97,y:0.97,align:'right'}};
window._loadLayout=null;
async function loadingLoad(){
  try{
    const d=await A('GET','/api/loading/layout');
    const els=(d&&d.elements)||{};
    const L={};LOAD_ELS.forEach(k=>{L[k]=Object.assign({},LOAD_DEF[k],els[k]||{});});
    window._loadLayout=L;
  }catch(e){window._loadLayout=JSON.parse(JSON.stringify(LOAD_DEF));}
  const sl=document.getElementById('loadBarW');
  sl.value=Math.round((window._loadLayout.progress_bar.w||0.5)*100);
  document.getElementById('loadBarWVal').textContent=sl.value;
  // 预加载页与主菜单共用同一张背景图，直接复用它的预览接口
  document.getElementById('loadingBg').src='/api/login/bg/file?t='+Date.now();
  loadingRender();
}
function loadingRender(){
  const L=window._loadLayout;if(!L)return;
  const wrap=document.getElementById('loadingCanvasWrap');
  wrap.querySelectorAll('.load-el').forEach(el=>{
    const k=el.dataset.el,s=L[k]||{},align=s.align||'center';
    el.style.top=((s.y||0)*100)+'%';
    el.style.left=((s.x||0)*100)+'%';
    if(k==='progress_bar'){
      el.style.width=((s.w||0.5)*100)+'%';
      el.style.height=Math.max(6,(s.h||0.02)*(wrap.clientHeight||340))+'px';
      el.style.minWidth='0';
      el.style.transform='translateX(-50%)';
    }else{
      el.style.transform=align==='right'?'translateX(-100%)':(align==='center'?'translateX(-50%)':'none');
      el.style.textAlign=align==='right'?'right':(align==='left'?'left':'center');
    }
  });
}
function loadingInitDrag(){
  const wrap=document.getElementById('loadingCanvasWrap');
  wrap.querySelectorAll('.load-el').forEach(el=>{
    el.addEventListener('pointerdown',e=>{
      e.preventDefault();
      const k=el.dataset.el,r=wrap.getBoundingClientRect();
      if(!r.width||!r.height)return;
      const sx=e.clientX,sy=e.clientY,s0=Object.assign({},window._loadLayout[k]||{});
      const clamp=v=>Math.max(0,Math.min(1,v));
      const move=ev=>{
        const s=window._loadLayout[k]=window._loadLayout[k]||{};
        s.x=clamp((s0.x||0)+(ev.clientX-sx)/r.width);
        s.y=clamp((s0.y||0)+(ev.clientY-sy)/r.height);
        loadingRender();
      };
      const up=()=>{el.removeEventListener('pointermove',move);el.removeEventListener('pointerup',up);el.removeEventListener('pointercancel',up);
        show('loadingStat','已拖动【'+k+'】，记得点「保存布局」',true);};
      el.addEventListener('pointermove',move);el.addEventListener('pointerup',up);el.addEventListener('pointercancel',up);
      try{el.setPointerCapture(e.pointerId);}catch(_){}
    });
  });
}
document.getElementById('loadBarW').addEventListener('input',e=>{
  const v=parseInt(e.target.value,10)||50;
  document.getElementById('loadBarWVal').textContent=v;
  const s=window._loadLayout.progress_bar=window._loadLayout.progress_bar||{};
  s.w=v/100;loadingRender();
});
async function loadingSave(){
  const L=window._loadLayout;if(!L){show('loadingStat','布局尚未加载',false);return;}
  const elements={};
  LOAD_ELS.forEach(k=>{
    const s=L[k]||{},o={x:s.x!==undefined?s.x:LOAD_DEF[k].x,y:s.y!==undefined?s.y:LOAD_DEF[k].y};
    if(k==='progress_bar'){o.w=s.w!==undefined?s.w:0.5;o.h=s.h!==undefined?s.h:0.02;o.align='center';}
    else o.align=s.align||LOAD_DEF[k].align;
    elements[k]=o;
  });
  const r=await A('POST','/api/loading/layout',{elements});
  show('loadingStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
}
async function loadingReset(){
  if(!confirm('把预加载界面的 4 个元素恢复成默认位置？'))return;
  window._loadLayout=JSON.parse(JSON.stringify(LOAD_DEF));
  const sl=document.getElementById('loadBarW');sl.value=50;
  document.getElementById('loadBarWVal').textContent='50';
  loadingRender();
  const r=await A('POST','/api/loading/layout',{elements:JSON.parse(JSON.stringify(LOAD_DEF))});
  show('loadingStat',(r&&r.msg)?r.msg:'已恢复默认',!!(r&&r.ok));
}
loadingInitDrag();

// ---------- HUD 布局（四面板默认位置 + 缩放，参考分辨率 1920x1080） ----------
const HUD_KEYS=['status_card','quest_track','top_right_menu','skill_bar'];
const HUD_LABEL={status_card:'状态卡',quest_track:'任务追踪',top_right_menu:'右上菜单',skill_bar:'技能栏'};
// 各面板在参考分辨率下的设计尺寸（scale=1 时），用于编辑器按比例预览缩放
const HUD_BASE={status_card:[340,318],quest_track:[300,360],top_right_menu:[220,40],skill_bar:[360,48]};
const HUD_SCALE_MIN=0.6, HUD_SCALE_MAX=2.5;
const HUD_W=1920, HUD_H=1080;
window._hudLayout=null;
async function hudLoad(){
  try{
    const d=await A('GET','/api/hud/layout');
    const ps=(d&&d.panels)||{};
    const L={};HUD_KEYS.forEach(k=>{L[k]=Object.assign({x:0,y:0,scale:1},ps[k]||{});});
    window._hudLayout=L;
  }catch(e){ window._hudLayout={status_card:{x:12,y:12,scale:1},quest_track:{x:12,y:362,scale:1},top_right_menu:{x:1700,y:12,scale:1},skill_bar:{x:782,y:980,scale:1}}; }
  hudRender();
}
function hudRender(){
  const L=window._hudLayout;if(!L)return;
  const wrap=document.getElementById('hudCanvas');
  const cw=wrap.clientWidth||960;
  const sx=cw/HUD_W; // 画布像素/参考像素（16:9 下 sx≈sy）
  wrap.querySelectorAll('.hud-el').forEach(el=>{
    const k=el.dataset.el,s=L[k]||{x:0,y:0,scale:1};
    const base=HUD_BASE[k]||[200,120];
    el.style.left=((s.x||0)*sx)+'px';
    el.style.top=((s.y||0)*sx)+'px';
    el.style.width=Math.max(40,(base[0]*(s.scale||1)*sx))+'px';
    el.style.height=Math.max(24,(base[1]*(s.scale||1)*sx))+'px';
  });
}
function hudInitDrag(){
  const wrap=document.getElementById('hudCanvas');
  // 移动
  wrap.querySelectorAll('.hud-el').forEach(el=>{
    el.addEventListener('pointerdown',e=>{
      if(e.target.classList.contains('hud-rsz'))return; // 缩放手柄单独处理
      e.preventDefault();
      const k=el.dataset.el,r=wrap.getBoundingClientRect();
      if(!r.width||!r.height)return;
      const sx0=e.clientX,sy0=e.clientY,s0=Object.assign({},window._hudLayout[k]||{x:0,y:0});
      const clampW=v=>Math.max(0,Math.min(HUD_W,v));
      const clampH=v=>Math.max(0,Math.min(HUD_H,v));
      const move=ev=>{
        const s=window._hudLayout[k]=window._hudLayout[k]||{x:0,y:0,scale:1};
        s.x=Math.round(clampW(s0.x+(ev.clientX-sx0)/r.width*HUD_W));
        s.y=Math.round(clampH(s0.y+(ev.clientY-sy0)/r.height*HUD_H));
        hudRender();
      };
      const up=()=>{el.removeEventListener('pointermove',move);el.removeEventListener('pointerup',up);el.removeEventListener('pointercancel',up);
        show('hudStat','已拖动【'+(HUD_LABEL[k]||k)+'】，记得点「保存布局」',true);};
      el.addEventListener('pointermove',move);el.addEventListener('pointerup',up);el.addEventListener('pointercancel',up);
      try{el.setPointerCapture(e.pointerId);}catch(_){}
    });
  });
  // 缩放（拖右下角白点手柄）
  wrap.querySelectorAll('.hud-rsz').forEach(h=>{
    h.addEventListener('pointerdown',e=>{
      e.preventDefault();e.stopPropagation();
      const k=h.dataset.el,r=wrap.getBoundingClientRect();
      if(!r.width)return;
      const sx0=e.clientX,s0=Object.assign({},window._hudLayout[k]||{x:0,y:0,scale:1});
      const base=HUD_BASE[k]||[200,120];
      const pxPerRef=r.width/HUD_W;
      const startDrawnW=Math.max(1,base[0]*(s0.scale||1)*pxPerRef);
      const move=ev=>{
        const s=window._hudLayout[k]=window._hudLayout[k]||{x:0,y:0,scale:1};
        let ns=(startDrawnW+(ev.clientX-sx0))/(base[0]*pxPerRef);
        ns=Math.max(HUD_SCALE_MIN,Math.min(HUD_SCALE_MAX,ns));
        s.scale=Math.round(ns*100)/100;
        hudRender();
      };
      const up=()=>{h.removeEventListener('pointermove',move);h.removeEventListener('pointerup',up);h.removeEventListener('pointercancel',up);
        show('hudStat','已缩放【'+(HUD_LABEL[k]||k)+'】→ '+((window._hudLayout[k].scale||1).toFixed(2))+'x，记得点「保存布局」',true);};
      h.addEventListener('pointermove',move);h.addEventListener('pointerup',up);h.addEventListener('pointercancel',up);
      try{h.setPointerCapture(e.pointerId);}catch(_){}
    });
  });
}
async function hudSave(){
  const L=window._hudLayout;if(!L){show('hudStat','布局尚未加载',false);return;}
  const panels={};HUD_KEYS.forEach(k=>{const s=L[k]||{};panels[k]={x:Math.round(s.x||0),y:Math.round(s.y||0),scale:Math.round((s.scale||1)*100)/100};});
  const r=await A('POST','/api/hud/layout',{panels});
  show('hudStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
}
async function hudReset(){
  if(!confirm('把 HUD 四面板恢复成默认位置与大小（参考分辨率 1920×1080）？'))return;
  const r=await A('GET','/api/hud/layout');
  const ps=(r&&r.panels)||{};
  const L={};HUD_KEYS.forEach(k=>{L[k]=Object.assign({x:0,y:0,scale:1},ps[k]||{});});
  window._hudLayout=L;hudRender();
  const panels={};HUD_KEYS.forEach(k=>{const s=L[k]||{};panels[k]={x:Math.round(s.x||0),y:Math.round(s.y||0),scale:Math.round((s.scale||1)*100)/100};});
  const r2=await A('POST','/api/hud/layout',{panels});
  show('hudStat',(r2&&r2.msg)?r2.msg:'已恢复默认',!!(r2&&r2.ok));
}
hudInitDrag();

// ---------- 设置弹窗布局（数值化编辑） ----------
const SS_KEYS=['panel_max_width','panel_max_height','margin_x_ratio','margin_y_ratio','category_button_min_width','category_button_min_height'];
const SS_DEFAULTS={panel_max_width:960,panel_max_height:680,margin_x_ratio:0.08,margin_y_ratio:0.10,category_button_min_width:160,category_button_min_height:42};
async function settingsScreenLoad(){
  try{
    const d=await A('GET','/api/settings/layout');
    if(!d){show('settingsScreenStat','加载失败',false);return;}
    document.getElementById('ss_pw').value=d.panel_max_width??SS_DEFAULTS.panel_max_width;
    document.getElementById('ss_ph').value=d.panel_max_height??SS_DEFAULTS.panel_max_height;
    document.getElementById('ss_mx').value=d.margin_x_ratio??SS_DEFAULTS.margin_x_ratio;
    document.getElementById('ss_my').value=d.margin_y_ratio??SS_DEFAULTS.margin_y_ratio;
    document.getElementById('ss_bw').value=d.category_button_min_width??SS_DEFAULTS.category_button_min_width;
    document.getElementById('ss_bh').value=d.category_button_min_height??SS_DEFAULTS.category_button_min_height;
    show('settingsScreenStat','已加载设置弹窗布局',true);
  }catch(e){show('settingsScreenStat','加载失败：'+e,false);}
}
async function settingsScreenSave(){
  const r=await A('POST','/api/settings/layout',{
    panel_max_width:parseFloat(document.getElementById('ss_pw').value)||0,
    panel_max_height:parseFloat(document.getElementById('ss_ph').value)||0,
    margin_x_ratio:parseFloat(document.getElementById('ss_mx').value)||0,
    margin_y_ratio:parseFloat(document.getElementById('ss_my').value)||0,
    category_button_min_width:parseFloat(document.getElementById('ss_bw').value)||0,
    category_button_min_height:parseFloat(document.getElementById('ss_bh').value)||0,
  });
  show('settingsScreenStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
}
async function settingsScreenReset(){
  if(!confirm('把设置弹窗布局恢复成默认？'))return;
  const r=await A('POST','/api/settings/layout',SS_DEFAULTS);
  show('settingsScreenStat',(r&&r.msg)?r.msg:'已恢复默认',!!(r&&r.ok));
  settingsScreenLoad();
}

// ---------- 读档弹窗布局（数值化编辑） ----------
const SL_KEYS=['content_max_width','content_max_height','margin_x_ratio','margin_y_ratio','card_min_width','card_min_height'];
const SL_DEFAULTS={content_max_width:640,content_max_height:724,margin_x_ratio:0.0,margin_y_ratio:0.15,card_min_width:640,card_min_height:112};
async function saveloadScreenLoad(){
  try{
    const d=await A('GET','/api/saveload/layout');
    if(!d){show('saveloadScreenStat','加载失败',false);return;}
    document.getElementById('sl_pw').value=d.content_max_width??SL_DEFAULTS.content_max_width;
    document.getElementById('sl_ph').value=d.content_max_height??SL_DEFAULTS.content_max_height;
    document.getElementById('sl_mx').value=d.margin_x_ratio??SL_DEFAULTS.margin_x_ratio;
    document.getElementById('sl_my').value=d.margin_y_ratio??SL_DEFAULTS.margin_y_ratio;
    document.getElementById('sl_bw').value=d.card_min_width??SL_DEFAULTS.card_min_width;
    document.getElementById('sl_bh').value=d.card_min_height??SL_DEFAULTS.card_min_height;
    show('saveloadScreenStat','已加载读档弹窗布局',true);
  }catch(e){show('saveloadScreenStat','加载失败：'+e,false);}
}
async function saveloadScreenSave(){
  const r=await A('POST','/api/saveload/layout',{
    content_max_width:parseFloat(document.getElementById('sl_pw').value)||0,
    content_max_height:parseFloat(document.getElementById('sl_ph').value)||0,
    margin_x_ratio:parseFloat(document.getElementById('sl_mx').value)||0,
    margin_y_ratio:parseFloat(document.getElementById('sl_my').value)||0,
    card_min_width:parseFloat(document.getElementById('sl_bw').value)||0,
    card_min_height:parseFloat(document.getElementById('sl_bh').value)||0,
  });
  show('saveloadScreenStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
}
async function saveloadScreenReset(){
  if(!confirm('把读档弹窗布局恢复成默认？'))return;
  const r=await A('POST','/api/saveload/layout',SL_DEFAULTS);
  show('saveloadScreenStat',(r&&r.msg)?r.msg:'已恢复默认',!!(r&&r.ok));
  saveloadScreenLoad();
}

// ---------- 主菜单(登录)界面布局（自由拖拽可视化编辑） ----------
const MM_ELS=['title_group','menu_container','bottom_left','bottom_right'];
const MM_DEF={title_group:{anchor_left:0,anchor_top:0,anchor_right:0,anchor_bottom:0,offset_left:60,offset_top:48,offset_right:540,offset_bottom:220},
              menu_container:{anchor_left:0.06,anchor_top:0.32,anchor_right:0.42,anchor_bottom:0.78,offset_left:0,offset_top:0,offset_right:0,offset_bottom:0,separation:18},
              bottom_left:{anchor_left:0,anchor_top:1,anchor_right:0,anchor_bottom:1,offset_left:24,offset_top:-56,offset_right:360,offset_bottom:-32},
              bottom_right:{anchor_left:1,anchor_top:1,anchor_right:1,anchor_bottom:1,offset_left:-360,offset_top:-68,offset_right:-80,offset_bottom:-32}};
window._mmLayout=null;
async function mmLoad(){
  try{
    const d=await A('GET','/api/main_menu/layout');
    const els=(d&&d.elements)||{};
    const L={};MM_ELS.forEach(k=>{L[k]=Object.assign({},MM_DEF[k],els[k]||{});});
    window._mmLayout=L;
  }catch(e){window._mmLayout=JSON.parse(JSON.stringify(MM_DEF));}
  document.getElementById('mmBg').src='/api/login/bg/file?t='+Date.now();
  mmRender();
  mmInitDrag();
}
// 把归一化 anchor+offset 转成画布上的百分比矩形。
// 画布宽 Wc、高 Hc；某块左上角 px = anchor_left*Wc + offset_left；宽 = (anchor_right-anchor_left)*Wc + (offset_right-offset_left)
function mmRectCss(L,k,Wc,Hc){
  const s=L[k]||{};
  const left=s.anchor_left*Wc+s.offset_left;
  const top=s.anchor_top*Hc+s.offset_top;
  const width=(s.anchor_right-s.anchor_left)*Wc+(s.offset_right-s.offset_left);
  const height=(s.anchor_bottom-s.anchor_top)*Hc+(s.offset_bottom-s.offset_top);
  return {left,top,width,height};
}
function mmRender(){
  const L=window._mmLayout;if(!L)return;
  const wrap=document.getElementById('mmCanvasWrap');
  const Wc=wrap.clientWidth||720, Hc=wrap.clientHeight||405;
  wrap.querySelectorAll('.mm-el').forEach(el=>{
    const k=el.dataset.el;
    const r=mmRectCss(L,k,Wc,Hc);
    el.style.left=Math.max(0,r.left)+'px';
    el.style.top=Math.max(0,r.top)+'px';
    el.style.width=Math.max(20,r.width)+'px';
    el.style.height=Math.max(16,r.height)+'px';
    if(k==='menu_container'){
      document.getElementById('mmSepRow').style.display='';
      const sl=document.getElementById('mmSep');sl.value=L[k].separation||14;
      document.getElementById('mmSepVal').textContent=L[k].separation||14;
    }
  });
}
function mmInitDrag(){
  const wrap=document.getElementById('mmCanvasWrap');
  wrap.querySelectorAll('.mm-el').forEach(el=>{
    el.addEventListener('pointerdown',e=>{
      e.preventDefault();
      const k=el.dataset.el,r=wrap.getBoundingClientRect();
      if(!r.width||!r.height)return;
      const Wc=r.width,Hc=r.height;
      const s=window._mmLayout[k]=window._mmLayout[k]||{};
      const startLeft=parseFloat(el.style.left)||0,startTop=parseFloat(el.style.top)||0;
      const sx=e.clientX,sy=e.clientY;
      const move=ev=>{
        const dx=ev.clientX-sx, dy=ev.clientY-sy;
        // 反向解算：新左上 px → anchor/offset
        const newLeft=startLeft+dx, newTop=startTop+dy;
        const width=parseFloat(el.style.width)||80, height=parseFloat(el.style.height)||30;
        s.anchor_left=Math.max(0,Math.min(1,newLeft/Wc));
        s.anchor_top=Math.max(0,Math.min(1,newTop/Hc));
        s.offset_left=Math.max(-Wc,newLeft)-s.anchor_left*Wc;
        s.offset_top=Math.max(-Hc,newTop)-s.anchor_top*Hc;
        s.anchor_right=Math.max(s.anchor_left,Math.min(1,(newLeft+width)/Wc));
        s.anchor_bottom=Math.max(s.anchor_top,Math.min(1,(newTop+height)/Hc));
        s.offset_right=(newLeft+width)-s.anchor_right*Wc;
        s.offset_bottom=(newTop+height)-s.anchor_bottom*Hc;
        el.style.left=newLeft+'px';el.style.top=newTop+'px';
        show('mmStat','已拖动【'+k+'】，记得点「保存布局」',true);
      };
      const up=()=>{el.removeEventListener('pointermove',move);el.removeEventListener('pointerup',up);el.removeEventListener('pointercancel',up);};
      el.addEventListener('pointermove',move);el.addEventListener('pointerup',up);el.addEventListener('pointercancel',up);
      try{el.setPointerCapture(e.pointerId);}catch(_){}
    });
  });
}
document.getElementById('mmSep').addEventListener('input',e=>{
  const v=parseInt(e.target.value,10)||14;
  document.getElementById('mmSepVal').textContent=v;
  const s=window._mmLayout.menu_container=window._mmLayout.menu_container||{};
  s.separation=v;
});
async function mmSave(){
  const L=window._mmLayout;if(!L){show('mmStat','布局尚未加载',false);return;}
  const elements={};
  MM_ELS.forEach(k=>{
    const s=L[k]||{},d=MM_DEF[k];
    const o={};
    ['anchor_left','anchor_top','anchor_right','anchor_bottom','offset_left','offset_top','offset_right','offset_bottom'].forEach(c=>{
      o[c]=s[c]!==undefined?s[c]:d[c];
    });
    if(k==='menu_container')o.separation=s.separation!==undefined?s.separation:d.separation;
    elements[k]=o;
  });
  const r=await A('POST','/api/main_menu/layout',{elements});
  show('mmStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
}
async function mmReset(){
  if(!confirm('把主菜单四大块恢复成默认位置？'))return;
  window._mmLayout=JSON.parse(JSON.stringify(MM_DEF));
  mmRender();
  const r=await A('POST','/api/main_menu/layout',{elements:JSON.parse(JSON.stringify(MM_DEF))});
  show('mmStat',(r&&r.msg)?r.msg:'已恢复默认',!!(r&&r.ok));
}

// ---------- 主菜单资源替换 ----------
const MM_ASSET_LABELS={
  title_logo:'大标题 Logo（墨影江湖）',
  btn_hover_bg:'按钮悬停水墨笔触底板',
  icon_1:'图标 1 · 开始游戏',
  icon_2:'图标 2 · 继续游戏',
  icon_3:'图标 3 · 设置',
  icon_4:'图标 4 · 额外内容',
  icon_5:'图标 5 · 退出游戏'
};
async function mmAssetsLoad(){
  const box=document.getElementById('mmAssetsList'); if(!box)return;
  box.innerHTML='';
  try{
    const d=await A('GET','/api/main_menu/assets');
    Object.keys(MM_ASSET_LABELS).forEach(key=>{
      const label=MM_ASSET_LABELS[key];
      const isIcon=key.startsWith('icon_');
      let previewUrl='';
      if(isIcon){
        const idx=parseInt(key.split('_')[1],10)-1;
        const arr=(d&&d.icons)||[];
        if(arr[idx]) previewUrl='/api/main_menu/assets/file?key='+encodeURIComponent(key)+'&t='+Date.now();
      }else{
        if(d&&d[key]) previewUrl='/api/main_menu/assets/file?key='+encodeURIComponent(key)+'&t='+Date.now();
      }
      const preview=previewUrl?'<img src="'+previewUrl+'" style="max-height:64px;max-width:120px;border:1px solid #555;border-radius:6px">':'<span class="status">未设置（用默认）</span>';
      const row=document.createElement('div');
      row.style.cssText='display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:10px;background:var(--panel2);border:1px solid var(--line);border-radius:8px';
      row.innerHTML='<div style="width:220px;color:var(--muted)">'+label+'</div>'+
        '<div style="flex:1;min-width:120px">'+preview+'</div>'+
        '<div style="display:flex;align-items:center;gap:8px">'+
        '<input type="file" id="mmAsset_'+key+'" accept="image/*" style="flex:none;width:180px">'+
        '<button class="act" onclick="mmAssetReplace(\''+key+'\')">替换</button>'+
        (isIcon?'<button class="act sec" onclick="mmAssetClearIcon(\''+key+'\')">恢复默认</button>':'')+
        '</div>';
      box.appendChild(row);
    });
  }catch(e){box.innerHTML='<div class="status bad">读取失败：'+e+'</div>';}
}
async function mmAssetReplace(key){
  const inp=document.getElementById('mmAsset_'+key);
  if(!inp||!inp.files[0]){show('mmAssetsStat','请先选一张图片',false);return;}
  const f=inp.files[0];
  const d=await f.arrayBuffer(); const b64=bufToB64(d);
  const r=await A('POST','/api/main_menu/assets/replace',{key:key,data:b64});
  show('mmAssetsStat',(r&&r.msg)?r.msg:(r&&r.ok?'已替换':'失败'),!!(r&&r.ok));
  if(r&&r.ok){mmAssetsLoad();}
}
async function mmAssetClearIcon(key){
  const idx=parseInt(key.split('_')[1],10)||0;
  if(!confirm('恢复 '+MM_ASSET_LABELS[key]+' 为默认路径？'))return;
  const r=await A('POST','/api/main_menu/assets/clear_icon',{idx:idx});
  show('mmAssetsStat',(r&&r.msg)?r.msg:(r&&r.ok?'已恢复':'失败'),!!(r&&r.ok));
  if(r&&r.ok)mmAssetsLoad();
}

// ---------- 战棋布局编辑器 ----------
window._bl=null;        // 当前布局 {id,name,view_mode,width,height,obstacles[],heights[],deployment{}}
window._blSel=null;     // 当前选中布局 id
function blLoadList(){
  A('GET','/api/battle_layout/list').then(list=>{
    const box=document.getElementById('blList');box.innerHTML='';
    (list||[]).forEach(it=>{
      const d=document.createElement('div');d.className='item';d.textContent=it.name+' ('+it.width+'×'+it.height+', '+(it.view_mode==='ortho'?'方块':'菱形')+(it.has_bg?', 有底图':'')+')';
      d.onclick=()=>blLoadOne(it.id);
      box.appendChild(d);
    });
    if(!list||!list.length){box.innerHTML='<div class="hint">暂无布局，点「＋ 新建」或右侧预设。</div>';}
  }).catch(()=>{});
}
async function blLoadOne(id){
  window._blSel=id;
  const d=await A('GET','/api/battle_layout?id='+encodeURIComponent(id));
  window._bl=d;
  document.getElementById('blView').value=d.view_mode||'iso';
  document.getElementById('blW').value=d.width||10;
  document.getElementById('blH').value=d.height||8;
  if(window._bl.pan_x===undefined)window._bl.pan_x=0;
  if(window._bl.pan_y===undefined)window._bl.pan_y=0;
  if(window._bl.zoom===undefined)window._bl.zoom=1.0;
  if(window._bl.rotation===undefined)window._bl.rotation=0;
  if(window._bl.bg_rotate===undefined)window._bl.bg_rotate=false;
  const syncEl=document.getElementById('blBgSync'); if(syncEl)syncEl.checked=!!window._bl.bg_rotate;
  document.getElementById('blZoomVal').textContent=Math.round((window._bl.zoom||1)*100);
  const r0=Math.round((window._bl.rotation||0)*100)/100;
  document.getElementById('blRotVal').textContent=r0;
  const ri=document.getElementById('blRotInput'); if(ri)ri.value=r0;
  blRender();
  const cnt=document.getElementById('blGridCount');
  if(cnt)cnt.textContent='当前 '+window._bl.width+'×'+window._bl.height+' = '+(window._bl.width*window._bl.height)+' 格';
  blLoadBg();
}
function blLoadBg(){
  const img=document.getElementById('blBg');
  if(window._bl && window._bl.background){
    img.src='/api/battle_bg/file?id='+encodeURIComponent(window._blSel)+'&t='+Date.now();
    img.style.display='';
  }else{img.style.display='none';img.src='';}
}
function blNewPrompt(){
  const id=prompt('新布局 id（英文/数字，如 forest_ambush）：','new_layout');
  if(!id)return;
  const w=parseInt(document.getElementById('blW').value,10)||10;
  const h=parseInt(document.getElementById('blH').value,10)||8;
  A('POST','/api/battle_layout/save',{id,data:{name:id,view_mode:document.getElementById('blView').value,width:w,height:h,obstacles:[],heights:[],deployment:{}}}).then(r=>{
    if(r&&r.ok){blLoadList();blLoadOne(id);}else show('blStat',(r&&r.msg)||'失败',false);
  });
}
async function blPreset(n){
  const r=await A('POST','/api/battle_layout/preset',{size:n});
  show('blStat',(r&&r.msg)?r.msg:'已生成预设',!!(r&&r.ok));
  if(r&&r.ok){blLoadList();blLoadOne('preset_'+n+'x'+n);}
}
function blViewChanged(){
  if(window._bl)window._bl.view_mode=document.getElementById('blView').value;
  blRender();
}
function blResize(){
  if(!window._bl){show('blStat','先选或新建一个布局',false);return;}
  window._bl.width=Math.max(2,Math.min(40,parseInt(document.getElementById('blW').value,10)||window._bl.width));
  window._bl.height=Math.max(2,Math.min(40,parseInt(document.getElementById('blH').value,10)||window._bl.height));
  document.getElementById('blW').value=window._bl.width;
  document.getElementById('blH').value=window._bl.height;
  blClipTerrain();
  blRender();
  const cnt=document.getElementById('blGridCount');
  if(cnt)cnt.textContent='当前 '+window._bl.width+'×'+window._bl.height+' = '+(window._bl.width*window._bl.height)+' 格';
}
// 场景适配：一键套用某战术长宽比（开阔战场/狭路/据点/突围/横列），立即重算并裁剪越界地形
function blApplyScene(w,h){
  if(!window._bl){show('blStat','先选或新建一个布局',false);return;}
  document.getElementById('blW').value=w;
  document.getElementById('blH').value=h;
  window._bl.width=w;window._bl.height=h;
  blClipTerrain();
  blRender();
  const cnt=document.getElementById('blGridCount');
  if(cnt)cnt.textContent='当前 '+w+'×'+h+' = '+(w*h)+' 格（场景预设）';
}
// 长宽对调：把 W/H 两个数字互换（一次输入不合理直接点此即可翻转），并立即重算
function blSwapWH(){
  if(!window._bl){show('blStat','先选或新建一个布局',false);return;}
  const w=window._bl.width, h=window._bl.height;
  window._bl.width=h; window._bl.height=w;
  document.getElementById('blW').value=h;
  document.getElementById('blH').value=w;
  blClipTerrain();
  blRender();
  const cnt=document.getElementById('blGridCount');
  if(cnt)cnt.textContent='当前 '+window._bl.width+'×'+window._bl.height+' = '+(window._bl.width*window._bl.height)+' 格（已对调）';
}
function blClipTerrain(){
  const W=window._bl.width,H=window._bl.height;
  window._bl.obstacles=(window._bl.obstacles||[]).filter(s=>{const p=s.split(',');return +p[0]<W&&+p[1]<H;});
  window._bl.heights=(window._bl.heights||[]).filter(s=>{const p=s.split(',');return +p[0]<W&&+p[1]<H;});
}
function blClearTerrain(){
  if(!window._bl)return;
  window._bl.obstacles=[];window._bl.heights=[];blRender();
}
// 网格几何：把 cell(i,j) 投到 720p 画布坐标（与游戏侧 BattleGrid 同公式）
// 含用户平移(pan_x/pan_y，像素)、缩放(zoom，倍率)、旋转(rotation，度，绕画布中心)：先算基准居中坐标，再乘 zoom、加 pan、最后绕中心旋转。
function blCellToXY(i,j){
  const wrap=document.getElementById('blCanvasWrap');
  const Wc=wrap.clientWidth||720, Hc=wrap.clientHeight||405;
  const W=window._bl.width, H=window._bl.height;
  const isIso=window._bl.view_mode!=='ortho';
  const zoom=window._bl.zoom||1.0;
  const panX=window._bl.pan_x||0, panY=window._bl.pan_y||0;
  const rot=window._bl.rotation||0;
  // 单元像素尺寸：让整张网格铺满画布 92%（基准，未缩放前）
  let s;
  if(isIso){ s=Math.min(Wc*0.92/(W+H), Hc*0.92/((W+H)*0.5)); }
  else { s=Math.min(Wc*0.92/W, Hc*0.92/H); }
  const tw=s*zoom, th=(isIso?s*0.5:s)*zoom;
  let x,y;
  if(isIso){ x=(i-j)*tw*0.5; y=(i+j)*th*0.5; }
  else { x=i*tw; y=j*th; }
  // 居中（先以画布中心为原点）
  const cx=Wc*0.5, cy=Hc*0.5;
  let dx=(x) - ((isIso?((W-1)-(0))*tw*0.5: (W-1)*tw*0.5))*0.5 + panX;
  let dy=(y) - ((isIso?((W-1)+(H-1))*th*0.5: (H-1)*th*0.5))*0.5 + panY;
  // 绕画布中心旋转（顺时针为正，屏幕坐标 y 向下）
  if(rot){
    const r=rot*Math.PI/180, cs=Math.cos(r), sn=Math.sin(r);
    const rx=dx*cs - dy*sn, ry=dx*sn + dy*cs;
    dx=rx; dy=ry;
  }
  return {x:cx+dx, y:cy+dy, tw, th, isIso};
}
function blXYToCell(px,py){
  const wrap=document.getElementById('blCanvasWrap');
  const Wc=wrap.clientWidth||720, Hc=wrap.clientHeight||405;
  const W=window._bl.width, H=window._bl.height;
  const isIso=window._bl.view_mode!=='ortho';
  const zoom=window._bl.zoom||1.0;
  const panX=window._bl.pan_x||0, panY=window._bl.pan_y||0;
  const rot=window._bl.rotation||0;
  let s;
  if(isIso){ s=Math.min(Wc*0.92/(W+H), Hc*0.92/((W+H)*0.5)); }
  else { s=Math.min(Wc*0.92/W, Hc*0.92/H); }
  const tw=s*zoom, th=(isIso?s*0.5:s)*zoom;
  // 先以画布中心为原点，逆旋转回未旋转空间，再走原居中+pan 反算
  let dx=px-Wc*0.5, dy=py-Hc*0.5;
  if(rot){
    const r=-rot*Math.PI/180, cs=Math.cos(r), sn=Math.sin(r);
    const rx=dx*cs - dy*sn, ry=dx*sn + dy*cs;
    dx=rx; dy=ry;
  }
  const ox=((isIso?((W-1)-(0))*tw*0.5: (W-1)*tw*0.5))*0.5;
  const oy=((isIso?((W-1)+(H-1))*th*0.5: (H-1)*th*0.5))*0.5;
  const lx=dx+ox-panX, ly=dy+oy-panY;
  let gx,gy;
  if(isIso){
    gx=Math.round((lx/tw + ly/th)*0.5);
    gy=Math.round((ly/th - lx/tw)*0.5);
  }else{
    gx=Math.floor(lx/tw); gy=Math.floor(ly/th);
  }
  if(gx<0||gy<0||gx>=W||gy>=H)return null;
  return {x:gx,y:gy};
}
function blHas(arr,key){return (arr||[]).indexOf(key)>=0;}
// 高地数组元素是 "x,y,h" 格式，渲染判断要用 "x,y" 前缀匹配（修复：原 blHas 整串匹配导致高地永远画不出）
function blHasPrefix(arr,key){return (arr||[]).some(s=>String(s).startsWith(key+','));}
function blRender(){
  const c=document.getElementById('blCanvas');if(!c||!window._bl)return;
  const wrap=document.getElementById('blCanvasWrap');
  c.width=wrap.clientWidth||720; c.height=wrap.clientHeight||405;
  const ctx=c.getContext('2d');
  ctx.clearRect(0,0,c.width,c.height);
  // 底图大背景默认与棋盘解绑（固定不转）；勾选「场景底图跟随旋转」后才一起转
  const bgEl=document.getElementById('blBg');
  if(bgEl)bgEl.style.transform=(window._bl.bg_rotate?('rotate('+(window._bl.rotation||0)+'deg)'):'none');
  const W=window._bl.width,H=window._bl.height;
  const obs=window._bl.obstacles||[], hs=window._bl.heights||[];
  const rotRad=(window._bl.rotation||0)*Math.PI/180;
  for(let j=0;j<H;j++)for(let i=0;i<W;i++){
    const g=blCellToXY(i,j);
    const hw=g.tw*0.5, hh=g.th*0.5;
    // 每个格子的形状也绕自身中心旋转同样角度 → 整张棋盘作为刚体旋转，格子外观不变形
    ctx.save();
    if(rotRad){ ctx.translate(g.x,g.y); ctx.rotate(rotRad); ctx.translate(-g.x,-g.y); }
    ctx.beginPath();
    if(g.isIso){ctx.moveTo(g.x,g.y-hh);ctx.lineTo(g.x+hw,g.y);ctx.lineTo(g.x,g.y+hh);ctx.lineTo(g.x-hw,g.y);}
    else{ctx.rect(g.x-hw,g.y-hh,g.tw,g.th);}
    ctx.closePath();
    const key=i+','+j;
    if(blHas(obs,key)){ctx.fillStyle='rgba(200,60,50,0.55)';}
    else if(blHasPrefix(hs,key)){ctx.fillStyle='rgba(230,179,90,0.55)';}
    else{ctx.fillStyle='rgba(70,110,180,0.35)';}
    ctx.fill();
    ctx.strokeStyle='rgba(180,200,230,0.5)';ctx.lineWidth=1;ctx.stroke();
    ctx.restore();
  }
  // 单位落点预览
  const u=document.getElementById('blUnit');
  if(window._bl.deployment && window._bl.deployment.player){
    const p=window._bl.deployment.player;const g=blCellToXY(p[0],p[1]);
    u.style.display='';u.style.left=(g.x-9)+'px';u.style.top=(g.y-9)+'px';
  }else{u.style.display='none';}
}
function blPaintAt(px,py){
  if(!window._bl)return;
  const cell=blXYToCell(px,py);if(!cell)return;
  const key=cell.x+','+cell.y;
  const mode=(document.querySelector('input[name=blPaint]:checked')||{}).value||'walk';
  let obs=window._bl.obstacles||[], hs=window._bl.heights||[];
  obs=obs.filter(s=>s!==key); hs=hs.filter(s=>s.split(',')[0]+','+s.split(',')[1]!==key);
  if(mode==='obstacle')obs.push(key);
  else if(mode==='high')hs.push(key+',1');
  window._bl.obstacles=obs;window._bl.heights=hs;
  blRender();
}
function blInitCanvas(){
  const wrap=document.getElementById('blCanvasWrap');
  const c=document.getElementById('blCanvas');
  let painting=false;
  c.addEventListener('pointerdown',e=>{painting=true;const r=c.getBoundingClientRect();blPaintAt(e.clientX-r.left,e.clientY-r.top);});
  c.addEventListener('pointermove',e=>{if(painting){const r=c.getBoundingClientRect();blPaintAt(e.clientX-r.left,e.clientY-r.top);}});
  c.addEventListener('pointerup',()=>painting=false);
  c.addEventListener('pointerleave',()=>painting=false);
  // 单位拖动
  const u=document.getElementById('blUnit');
  u.addEventListener('pointerdown',e=>{
    e.preventDefault();e.stopPropagation();
    const sx=e.clientX,sy=e.clientY;
    const sp={x:parseFloat(u.style.left)||0,y:parseFloat(u.style.top)||0};
    const mv=ev=>{u.style.left=(sp.x+ev.clientX-sx)+'px';u.style.top=(sp.y+ev.clientY-sy)+'px';};
    const up=ev=>{
      document.removeEventListener('pointermove',mv);document.removeEventListener('pointerup',up);
      if(!window._bl)return;
      const r=wrap.getBoundingClientRect();
      const cell=blXYToCell(ev.clientX-r.left,ev.clientY-r.top);
      if(cell){window._bl.deployment=window._bl.deployment||{};window._bl.deployment.player=[cell.x,cell.y];blRender();}
    };
    document.addEventListener('pointermove',mv);document.addEventListener('pointerup',up);
    try{u.setPointerCapture(e.pointerId);}catch(_){}
  });
}
blInitCanvas();
// ---- 临时立绘测试（教头演示战棋出场角色）----
async function dpLoad(){
  const list=await A('GET','/api/demo_portrait/list');
  const box=document.getElementById('dpList');box.innerHTML='';
  (list||[]).forEach(it=>{
    const card=document.createElement('div');
    card.style.cssText='border:1px solid #444;border-radius:8px;padding:8px;min-width:200px;background:#0e1119';
    const img=document.createElement('img');
    img.style.cssText='width:120px;height:120px;object-fit:contain;background:#1a1d28;border-radius:6px;display:block';
    if(it.current){img.src='/api/demo_portrait/file?kind='+encodeURIComponent(it.kind)+'&t='+Date.now();}
    else{img.alt='（默认/缺图）';img.style.opacity='0.4';}
    const t=document.createElement('div');t.textContent=it.label;t.style.cssText='margin:6px 0 4px;color:#ccd2e6;font-size:13px';
    const up=document.createElement('input');up.type='file';up.accept='image/*';
    const btn=document.createElement('button');btn.className='act';btn.textContent='上传替换';
    btn.onclick=async()=>{
      if(!up.files||!up.files[0]){alert('先选一张图片');return;}
      const fr=new FileReader();
      fr.onload=async()=>{
        const b64=fr.result.split(',')[1];
        const r=await A('POST','/api/demo_portrait/upload',{kind:it.kind,data:b64,filename:up.files[0].name});
        show('blStat',(r&&r.msg)?r.msg:(r&&r.ok?'已替换':'失败'),!!(r&&r.ok));
        if(r&&r.ok)dpLoad();
      };
      fr.readAsDataURL(up.files[0]);
    };
    const rst=document.createElement('button');rst.className='act sec';rst.textContent='恢复默认';
    rst.onclick=async()=>{
      const r=await A('POST','/api/demo_portrait/reset',{kind:it.kind});
      show('blStat',(r&&r.msg)?r.msg:'已恢复',!!(r&&r.ok));
      if(r&&r.ok)dpLoad();
    };
    const row=document.createElement('div');row.style.cssText='display:flex;gap:6px;margin-top:4px';
    row.appendChild(btn);row.appendChild(rst);
    card.appendChild(img);card.appendChild(t);card.appendChild(up);card.appendChild(row);
    box.appendChild(card);
  });
  if(!(list||[]).length)box.innerHTML='<div class="hint">无可用立绘目标</div>';
}
// ---- 棋盘平移 / 缩放 ----
function blPan(dx,dy){
  if(!window._bl)return;
  window._bl.pan_x=(window._bl.pan_x||0)+dx*12;
  window._bl.pan_y=(window._bl.pan_y||0)+dy*12;
  blRender();
}
function blZoom(dz){
  if(!window._bl)return;
  window._bl.zoom=Math.max(0.2,Math.min(4.0,(window._bl.zoom||1.0)+dz));
  document.getElementById('blZoomVal').textContent=Math.round(window._bl.zoom*100);
  blRender();
}
function blResetTrans(){
  if(!window._bl)return;
  window._bl.pan_x=0;window._bl.pan_y=0;window._bl.zoom=1.0;
  document.getElementById('blZoomVal').textContent='100';
  blRender();
}
// 棋盘旋转：顺时针 +deg / 逆时针 -deg（90° 步进最贴合战棋；任意角度也支持）。绕画布中心旋转。
function blRotSync(){
  const r=window._bl.rotation||0;
  const disp=Math.round(r*100)/100;
  document.getElementById('blRotVal').textContent=disp;
  const inp=document.getElementById('blRotInput');
  if(inp)inp.value=disp;
  blRender();
}
function blRotate(deg){
  if(!window._bl)return;
  // 步进按钮保持整洁：归一到 0-360，但不丢小数精度
  let r=((window._bl.rotation||0)+deg)%360; if(r<0)r+=360;
  window._bl.rotation=r;
  blRotSync();
}
function blSetRot(){
  if(!window._bl)return;
  const inp=document.getElementById('blRotInput');
  let v=parseFloat(inp.value);
  if(isNaN(v))v=0;
  window._bl.rotation=v;   // 精确值原样保留（支持小数/负角/任意角度）
  blRotSync();
}
function blRotLive(){
  if(!window._bl)return;
  let v=parseFloat(document.getElementById('blRotInput').value);
  if(isNaN(v))return;
  window._bl.rotation=v;
  document.getElementById('blRotVal').textContent=Math.round(v*100)/100;
  blRender();
}
function blResetRot(){
  if(!window._bl)return;
  window._bl.rotation=0;
  blRotSync();
}
function blBgSyncToggle(){
  if(!window._bl)return;
  const el=document.getElementById('blBgSync');
  window._bl.bg_rotate=!!(el&&el.checked);
  blRender();
}
async function blSave(){
  if(!window._bl||!window._blSel){show('blStat','先选或新建布局',false);return;}
  const d=window._bl;
  // 保留已上传的底图：上传底图时 background 已写入布局 json，但保存 payload 不含该字段，
  // 若在此不回填，battle_layout_save 归一化会把 background 覆盖成空 → 底图丢失。
  const bg = (d.background && String(d.background).trim() != "") ? d.background : "";
  const payload={id:window._blSel,data:{name:d.name||window._blSel,view_mode:d.view_mode,width:d.width,height:d.height,pan_x:d.pan_x||0,pan_y:d.pan_y||0,zoom:d.zoom||1.0,rotation:d.rotation||0,bg_rotate:!!d.bg_rotate,background:bg,obstacles:d.obstacles||[],heights:d.heights||[],deployment:d.deployment||{}}};
  const r=await A('POST','/api/battle_layout/save',payload);
  show('blStat',(r&&r.msg)?r.msg:(r&&r.ok?'已保存':'失败'),!!(r&&r.ok));
  if(r&&r.ok)blLoadList();
}
async function blDelete(){
  if(!window._blSel)return;
  if(!confirm('删除布局「'+window._blSel+'」？（已备份到回收站）'))return;
  const r=await A('POST','/api/battle_layout/delete',{id:window._blSel});
  show('blStat',(r&&r.msg)?r.msg:'已删除',!!(r&&r.ok));
  if(r&&r.ok){window._bl=null;blRender();blLoadList();}
}
async function blBgUpload(){
  if(!window._blSel){show('blStat','先选或新建布局',false);return;}
  const inp=document.getElementById('blBgFile');
  if(!inp.files||!inp.files[0]){show('blStat','请先选一张图片',false);return;}
  const fr=new FileReader();
  fr.onload=async()=>{
    const b64=fr.result.split(',')[1];
    const r=await A('POST','/api/battle_bg/upload',{id:window._blSel,data:b64,filename:inp.files[0].name});
    show('blStat',(r&&r.msg)?r.msg:(r&&r.ok?'已上传':'失败'),!!(r&&r.ok));
    if(r&&r.ok){const d=await A('GET','/api/battle_layout?id='+encodeURIComponent(window._blSel));window._bl=d;blLoadBg();}
  };
  fr.readAsDataURL(inp.files[0]);
}
async function blBgClear(){
  if(!window._blSel)return;
  const r=await A('POST','/api/battle_bg/clear',{id:window._blSel});
  show('blStat',(r&&r.msg)?r.msg:'已清除',!!(r&&r.ok));
  if(r&&r.ok){window._bl.background='';blLoadBg();}
}

// ---------- LOG ----------
async function logLoad(){const l=await A('GET','/api/log');
  const html=(l||[]).slice().reverse().map(x=>`<div class="logline"><b>${x.ts.replace('T',' ')}</b> ［${x.action}］ ${x.target} ${x.detail||''}</div>`).join('');
  const fb=document.getElementById('logBoxFloat'); if(fb) fb.innerHTML=html||'<div class="olf-empty">暂无操作记录</div>';
  const lb=document.getElementById('logBox'); if(lb) lb.innerHTML=html;}
function opLogToggle(){const el=document.getElementById('opLogFloat');if(!el)return;
  el.classList.toggle('collapsed');
  const t=document.getElementById('olfToggle');if(t)t.textContent=el.classList.contains('collapsed')?'▸':'▾';}
let _opLogSig='';let _opLogTimer=null;
async function opLogAutoRefresh(){let d;try{d=await A('GET','/api/log');}catch(e){return;}
  if(!Array.isArray(d))return;const sig=JSON.stringify(d.map(x=>x.ts+x.action+x.target));
  if(sig===_opLogSig)return;_opLogSig=sig;logLoad();}
function _startOpLogAutoRefresh(){if(_opLogTimer)return;
  _opLogTimer=setInterval(()=>{if(document.visibilityState!=='hidden')opLogAutoRefresh();},30000);}

// ===== 待办清单自动刷新（2026-09-02 新增）：每 30 秒静默比对，数据有变化才重渲染，
// 保留用户当前视图（按轻重缓急/按模块）与选中模块，避免状态标记滞后需手动刷新 =====
let BL_VIEW='priority';
let BL_CUR='';
let _blSig='';
let _blTimer=null;
async function backlogAutoRefresh(){
  let d; try{ d=await A('GET','/api/backlog'); }catch(e){ return; }
  if(!d||!d.ok) return;
  const sig=JSON.stringify(d.modules.map(m=>m.items.map(it=>it.title+'='+it.status).join('|')).join(';'));
  if(sig===_blSig) return;   // 数据无变化，不打扰当前画面
  _blSig=sig;
  backlogLoad();             // 有变化才重渲染（保留 BL_VIEW/BL_CUR）
}
function _startBacklogAutoRefresh(){
  if(_blTimer) return;
  _blTimer=setInterval(()=>{ if(document.visibilityState!=='hidden') backlogAutoRefresh(); }, 30000);
}

async function backlogLoad(){
  const box=document.getElementById('backlogRoot'); if(!box) return;
  const sw=document.getElementById('blViewSwitch');
  let d; try{ d=await A('GET','/api/backlog'); }catch(e){ box.textContent='加载失败'; return; }
  if(!d||!d.ok){ box.innerHTML='<div style="padding:20px;color:#9aa0b8">'+((d&&d.error)||'无数据')+'</div>'; return; }
  _blSig=JSON.stringify(d.modules.map(m=>m.items.map(it=>it.title+'='+it.status).join('|')).join(';'));
  const TC={待办:'#60a5fa',隐性BUG:'#f87171',未实现:'#fbbf24',占位:'#c084fc',优化建议:'#34d399'};
  const SL={open:'未开始/进行中',blocked:'受阻',done:'已完成'};
  const _WHY={'待办':'处理它能让对应系统更完善、少留隐患。','隐性BUG':'这类问题最阴险：表面不报错，但实际行为不对，越早修越省事。','未实现':'补上后这个功能才真正能用，否则只是空壳。','占位':'替换掉临时占位，界面/体验才完整、才像正式作品。','优化建议':'不阻塞流程，但做了能明显提升性能或手感。'};
  const _MISS={'待办':'待排期开始。','隐性BUG':'还没合入修复补丁。','未实现':'真实逻辑未落地。','占位':'真实资源/真实逻辑未到位。','优化建议':'待排期实施。'};
  function plainOf(it){
    const t=it.type||''; let progress,bugs;
    if(it.status==='done') progress='已完成 ✅（见本模块「已完成执行」）';
    else if(it.status==='blocked') progress='受阻：当前卡在依赖/未拍板（来源：'+(it.source||'')+'）。';
    else progress='尚未开始 / 进行中，还没真正落地。';
    if(t==='隐性BUG') bugs='⚠ 这就是个隐性BUG：'+(it.detail||'表面正常但行为异常。');
    else if(t==='占位') bugs='当前用占位实现（可能显示紫块/色块），不崩但非最终效果。';
    else if(t==='未实现') bugs='功能已预留但未实现，调到会走空逻辑/降级。';
    else bugs='暂无已知代码BUG，属待办/优化项。';
    const p=it.plain||{};
    return {what:p.what||(it.detail||it.title||''),why:p.why||(_WHY[t]||'完善项目的一部分。'),progress:p.progress||progress,missing:p.missing||(_MISS[t]||'待明确。'),plan:p.plan||(it.suggestion||'（待定，见建议/来源）'),bugs:p.bugs||bugs};
  }
  // ===== 轻重缓急分类（红=迫在眉睫 / 蓝=中规中矩 / 黄=影响较小或尚未开始） =====
  const PR=['red','blue','yellow'];
  const PCOLOR={red:'#f87171',blue:'#60a5fa',yellow:'#fbbf24'};
  const PLABEL={red:'🔴 迫在眉睫',blue:'🔵 中规中矩',yellow:'🟡 影响较小 / 未开始'};
  const PSHORT={red:'迫在眉睫',blue:'中规中矩',yellow:'影响小'};
  const _LOW=/待拍板|待决策|延后|Phase 3|Phase 4|谨慎|紧迫度极低|低优先级|后置|刻意延后/;
  function prioOf(it){
    if(it.status==='blocked') return 'red';                                   // 卡住整体进度 → 迫在眉睫
    if(it.type==='隐性BUG' && it.status==='open') return 'red';              // 表面不报错但行为异常 → 迫在眉睫
    if(it.type==='未实现') return 'blue';                                    // 功能缺口需落地 → 中规中矩
    if(it.type==='待办' && it.status==='open'){
      if(_LOW.test((it.title||'')+(it.detail||'')+(it.source||''))) return 'yellow'; // 待决策/后置/低紧迫 → 影响小
      return 'blue';
    }
    return 'yellow';                                                         // 占位/优化建议/已完成/已解决 → 影响小或无重大隐患
  }
  if(!BL_CUR) BL_CUR=d.modules[0].id;
  let cur=BL_CUR;
  let view=BL_VIEW;
  function cardHtml(it,isDone,prio,mName){
    const col=TC[it.type]||'#888';
    const ph=it.placeholder?' <span class="bl-pill">占位</span>':'';
    const st='<span class="bl-pill '+(it.status==='blocked'?'blocked':(it.status==='done'?'done':''))+'">'+(SL[it.status]||it.status)+'</span>';
    const pc=PCOLOR[prio]||'#888';
    const pbadge=isDone?'':('<span class="bl-pbadge" style="color:'+pc+';border-color:'+pc+'55;background:'+pc+'1a">'+PSHORT[prio]+'</span>');
    const mtag=mName?'<span class="bl-mtag">'+blEsc(mName)+'</span>':'';
    let h='<div class="bl-card'+(isDone?' done':'')+(prio?' prio-'+prio:'')+'"><div class="bl-top"><span class="bl-title">'+blEsc((isDone?'✅ ':'')+it.title)+'</span>';
    if(!isDone) h+=pbadge;
    h+=st+ph+mtag+'</div>';
    if(isDone){
      const dt=(it.resolvedAt||'').split(' ');
      const dd=dt[0]||'（未记录）'; const tt=dt[1]||'（未记录）';
      h+='<div class="bl-kv"><span class="bl-k">完成人：</span>'+blEsc(it.resolvedBy||'（未署名）')+'</div>';
      h+='<div class="bl-kv"><span class="bl-k">完成日期：</span>'+blEsc(dd)+'</div>';
      h+='<div class="bl-kv"><span class="bl-k">完成时间：</span>'+blEsc(tt)+'</div>';
      if(it.commit){
        h+='<div class="bl-kv"><span class="bl-k">日志定位：</span>commit '+blEsc(it.commit)+'</div>';
        h+='<div class="bl-trace"><div class="bl-trace-h">🔗 追溯 / 复原指引</div>'
          +'<code>git show '+blEsc(it.commit)+'</code><span class="bl-trace-note">看具体改了什么</span>'
          +'<code>git revert '+blEsc(it.commit)+'</code><span class="bl-trace-note">一键回退（出问题用）</span>'
          +'<div class="bl-trace-log">变更日志：docs/更改日志.md 中搜 '+blEsc(it.commit)+'</div></div>';
      }
      if(it.resolution) h+='<div class="bl-sug">解决说明：'+blEsc(it.resolution)+'</div>';
    } else {
      h+='<div class="bl-kv"><span class="bl-k">来源：</span>'+blEsc(it.source||'')+'</div>';
      const pl=plainOf(it);
      h+='<div class="bl-plain">'
        +plRow('📌 是干嘛的',pl.what)+plRow('💡 有什么用',pl.why)+plRow('🚦 执行到哪步',pl.progress)
        +plRow('🧩 还缺什么',pl.missing)+plRow('🛠 以后怎么解决',pl.plan)+plRow('🐞 当前BUG',pl.bugs)
        +'</div>';
    }
    h+='</div>';
    return h;
  }
  function plRow(k,v){return '<div class="bl-pl"><b>'+blEsc(k)+'</b><span>'+blEsc(v)+'</span></div>';}
  function styleBlock(){
    return '<style>.bl-card{background:#15182a;border:1px solid #2a2f47;border-radius:10px;padding:12px 14px;margin-bottom:10px}'
      +'.bl-card.done{background:#101b16;border-color:#1f3a2c}'
      +'.bl-card.prio-red{border-left:4px solid #f87171}.bl-card.prio-blue{border-left:4px solid #60a5fa}.bl-card.prio-yellow{border-left:4px solid #fbbf24}'
      +'.bl-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.bl-title{font-size:15px;font-weight:600}'
      +'.bl-badge{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;font-weight:600}'
      +'.bl-pbadge{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;font-weight:600}'
      +'.bl-pill{font-size:11px;padding:2px 8px;border-radius:999px;background:#1b1f33;border:1px solid #2a2f47;color:#9aa0b8}'
      +'.bl-pill.blocked{color:#f87171;border-color:#f8717155}.bl-pill.done{color:#34d399;border-color:#34d39955}'
      +'.bl-mtag{font-size:11px;padding:2px 8px;border-radius:999px;background:#1b1f33;border:1px solid #2a2f47;color:#9aa0b8;margin-left:auto}'
      +'.bl-kv{margin-top:6px;font-size:13px;color:#c7cbe0}.bl-k{color:#9aa0b8}'
      +'.bl-sug{margin-top:6px;font-size:13px;background:#1b1f33;border-left:3px solid #7c9cff;padding:6px 10px;border-radius:4px}'
      +'.bl-trace{margin-top:8px;background:#0e1714;border:1px solid #1f3a2c;border-radius:8px;padding:8px 10px;font-size:12px}'
      +'.bl-trace-h{color:#34d399;font-weight:700;margin-bottom:4px}'
      +'.bl-trace code{display:inline-block;background:#101b16;border:1px solid #2a2f47;border-radius:4px;padding:2px 6px;margin:2px 8px 2px 0;font-family:ui-monospace,Consolas,monospace;color:#9fe6c4}'
      +'.bl-trace-note{color:#9aa0b8;font-size:11px}'
      +'.bl-trace-log{margin-top:4px;color:#9aa0b8;font-size:11px}'
      +'.bl-chips{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px}.bl-chip{background:#15182a;border:1px solid #2a2f47;color:#e6e8f0;padding:6px 12px;border-radius:8px;cursor:pointer;font-size:13px}'
      +'.bl-chip.active{background:#7c9cff22;border-color:#7c9cff;color:#fff}'
      +'.bl-views{display:flex;gap:6px;margin-bottom:12px}'
      +'.bl-desc{color:#9aa0b8;font-size:13px;margin:0 0 12px}'
      +'.bl-grp{font-size:15px;font-weight:700;margin:16px 0 8px;padding-left:10px;border-left:4px solid #7c9cff}'
      +'.bl-grp.done{color:#34d399;border-left-color:#34d399}'
      +'.bl-grp.prio-red{color:#f87171;border-left-color:#f87171}.bl-grp.prio-blue{color:#60a5fa;border-left-color:#60a5fa}.bl-grp.prio-yellow{color:#fbbf24;border-left-color:#fbbf24}'
      +'.bl-plain{margin-top:8px;border-top:1px dashed #2a2f47;padding-top:6px}'
      +'.bl-pl{font-size:13px;margin:4px 0;display:flex;gap:6px}'
      +'.bl-pl b{color:#7c9cff;flex:0 0 96px;font-weight:600}</style>';
  }
  function render(){
    if(sw) sw.innerHTML='<span class="bl-chip'+(view==='priority'?' active':'')+'" data-v="priority">🔥 按轻重缓急</span><span class="bl-chip'+(view==='module'?' active':'')+'" data-v="module">🗂 按模块</span>';
    if(sw) sw.querySelectorAll('.bl-chip').forEach(ch=>ch.onclick=()=>{BL_VIEW=ch.dataset.v;view=BL_VIEW;render();});
    let h=styleBlock();
    if(view==='module'){
      const m=d.modules.find(x=>x.id===cur);
      h+='<div class="bl-chips">'+d.modules.map(m=>'<span class="bl-chip'+(m.id===cur?' active':'')+'" data-m="'+m.id+'">'+m.name+'</span>').join('')+'</div>';
      h+='<p class="bl-desc">'+(m.desc||'')+'</p>';
      const todo=m.items.filter(it=>it.status!=='done'&&it.status!=='resolved').slice().sort((a,b)=>PR.indexOf(prioOf(a))-PR.indexOf(prioOf(b)));
      const done=m.items.filter(it=>it.status==='done'||it.status==='resolved');
      if(todo.length){ h+='<div class="bl-grp">🟡 待解决 / 进行中（'+todo.length+'，已按轻重缓急排序）</div>'; todo.forEach(it=>h+=cardHtml(it,false,prioOf(it),null)); }
      if(done.length){ h+='<div class="bl-grp done">✅ 已完成执行（'+done.length+'）</div>'; done.forEach(it=>h+=cardHtml(it,true,null,null)); }
      if(!todo.length&&!done.length) h+='<div class="bl-desc">当前模块无条目</div>';
      box.innerHTML=h;
      box.querySelectorAll('.bl-chip[data-m]').forEach(ch=>ch.onclick=()=>{BL_CUR=ch.dataset.m;cur=BL_CUR;render();});
    } else {
      // 按轻重缓急：跨模块汇总所有待办项，红→蓝→黄 排序展示
      const all=[];
      d.modules.forEach(m=>m.items.forEach(it=>all.push({it,m})));
      const open=all.filter(x=>x.it.status!=='done'&&x.it.status!=='resolved');
      const done=all.filter(x=>x.it.status==='done'||x.it.status==='resolved');
      open.sort((a,b)=>PR.indexOf(prioOf(a.it))-PR.indexOf(prioOf(b.it)));
      ['red','blue','yellow'].forEach(band=>{
        const items=open.filter(x=>prioOf(x.it)===band);
        if(items.length){ h+='<div class="bl-grp prio-'+band+'">'+PLABEL[band]+'（'+items.length+'）</div>';
          items.forEach(x=>h+=cardHtml(x.it,false,band,x.m.name)); }
      });
      if(done.length){ h+='<div class="bl-grp done">✅ 已完成执行（'+done.length+'）</div>'; done.forEach(x=>h+=cardHtml(x.it,true,null,x.m.name)); }
      if(!open.length&&!done.length) h+='<div class="bl-desc">当前无待办条目</div>';
      box.innerHTML=h;
    }
  }
  render();
}
function blEsc(s){return (s==null?'':String(s)).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}

// ===== 派单传递板（2026-09-03 新增）：读 /api/handoff 快照，展示 + 认领 =====
async function handoffLoad(){
  const box=document.getElementById('handoffRoot'); if(!box) return;
  let d; try{ d=await A('GET','/api/handoff'); }catch(e){ box.textContent='加载失败'; return; }
  if(!d||!d.ok){ box.innerHTML='<div style="padding:20px;color:#9aa0b8">'+((d&&d.error)?blEsc(d.error):'无数据')+(d&&d.hint?('<br>'+blEsc(d.hint)):'')+'</div>'; return; }
  const G={open:['🔴 待认领','#f87171'],claimed:['🟡 进行中','#fbbf24'],done:['✅ 已完成','#34d399'],closed:['💤 已关闭','#9aa0b8']};
  function hfCard(it){
    const badges='<span class="hf-badge">'+blEsc(it.state)+'</span>'
      +(it.claim_by?'<span class="hf-badge">认领:'+blEsc(it.claim_by)+'</span>':'');
    const files=(it.files||[]).map(f=>'<code>'+blEsc(f)+'</code>').join(' ');
    const note=(it.note_done?('完成备注：'+blEsc(it.note_done)):(it.note_followup?('后续备注：'+blEsc(it.note_followup)):''));
    const claimBtn=(it.state==='open')?'<button class="act" onclick="hfClaim(\''+blEsc(it.id)+'\')">✋ 认领</button>':'';
    return '<div class="hf-card">'
      +'<div class="hf-top"><span class="hf-title">'+blEsc(it.title)+'</span>'+badges+'</div>'
      +'<div class="hf-route">'+blEsc(it.from)+' → '+blEsc(it.to)+'　·　'+blEsc(it.ts)+'</div>'
      +(it.desc?('<div class="hf-desc">'+blEsc(it.desc)+'</div>'):'')
      +(files?'<div class="hf-kv"><b>涉及文件</b>'+files+'</div>':'')
      +(it.verify?('<div class="hf-kv"><b>核验标准</b>'+blEsc(it.verify)+'</div>'):'')
      +(it.followup?('<div class="hf-kv"><b>后续依赖</b>'+blEsc(it.followup)+'</div>'):'')
      +(note?'<div class="hf-kv"><b>备注</b>'+note+'</div>':'')
      +'<div class="hf-act">'+claimBtn+'</div>'
      +'</div>';
  }
  let h='<style>.hf-grp{font-size:15px;font-weight:700;margin:16px 0 8px;padding-left:10px}'
    +'.hf-card{background:#15182a;border:1px solid #2a2f47;border-radius:10px;padding:12px 14px;margin-bottom:10px}'
    +'.hf-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.hf-title{font-size:15px;font-weight:600}'
    +'.hf-badge{font-size:11px;padding:2px 8px;border-radius:999px;background:#1b1f33;border:1px solid #2a2f47;color:#9aa0b8}'
    +'.hf-route{font-size:12px;color:#9aa0b8;margin:4px 0}'
    +'.hf-desc{font-size:13px;color:#c7cbe0;margin:6px 0;white-space:pre-wrap;max-height:200px;overflow:auto}'
    +'.hf-kv{font-size:13px;color:#c7cbe0;margin:4px 0}.hf-kv b{color:#7c9cff;margin-right:6px}'
    +'.hf-kv code{background:#101b16;border:1px solid #2a2f47;border-radius:4px;padding:1px 6px;margin:0 4px 2px 0;font-size:12px}'
    +'.hf-act{margin-top:8px}</style>';
  let any=false;
  for(const k of ['open','claimed','done','closed']){
    const items=d[k]||[];
    if(items.length){ any=true; h+='<div class="hf-grp" style="border-left:4px solid '+G[k][1]+';color:'+G[k][1]+'">'+G[k][0]+'（'+items.length+'）</div>'; items.forEach(it=>h+=hfCard(it)); }
  }
  if(!any) h+='<div class="bl-desc">当前无派单（open='+(d.open?d.open.length:0)+' claimed='+(d.claimed?d.claimed.length:0)+' done='+(d.done?d.done.length:0)+' closed='+(d.closed?d.closed.length:0)+'）</div>';
  box.innerHTML=h;
}
async function hfClaim(id){
  const by=(document.getElementById('hfBy')||{}).value||'工作室窗口';
  let d; try{ d=await A('POST','/api/handoff/claim',{id:id,by:by}); }catch(e){ alert('认领失败'); return; }
  if(!d||!d.ok){ alert('认领失败：'+((d&&d.error)||'')); return; }
  handoffLoad();
}
async function handoffRefresh(){
  let d; try{ d=await A('POST','/api/handoff/refresh',{}); }catch(e){ return; }
  handoffLoad();
}

// ---------- 协同启动卡（各 AI 窗口工作指令清单，数据来自 /api/startup_card） ----------
// 2026-09-02 重构：渲染为左侧隐藏栏里的点选列表，点窗口名即复制对应口令（见 tab-coord 结构）。
let STARTUP_DATA=null;
let _coordRailInit=false;
function _initCoordRail(){
  // 2026-09-02 v2：左栏固定常驻，不再悬停滑出，无需 mouseenter/leave 切换
  if(_coordRailInit) return; _coordRailInit=true;
}
function copyText(txt, btn){
  const done=(ok)=>{ if(btn){ const o=btn.textContent; btn.textContent=ok?'已复制 ✓':'复制失败'; setTimeout(()=>btn.textContent=o,1500); } };
  if(navigator.clipboard && navigator.clipboard.writeText){
    navigator.clipboard.writeText(txt).then(()=>done(true)).catch(()=>done(fallbackCopy(txt)));
  } else { done(fallbackCopy(txt)); }
}
function fallbackCopy(txt){
  try{ const ta=document.createElement('textarea'); ta.value=txt; ta.style.position='fixed'; ta.style.opacity='0';
       document.body.appendChild(ta); ta.select(); const ok=document.execCommand('copy'); document.body.removeChild(ta); return ok;
  }catch(e){ return false; }
}
async function loadStartupCard(){
  const list=document.getElementById('startupCardList'); if(!list) return;
  let data;
  try{ data=await A('GET','/api/startup_card'); }catch(e){ list.innerHTML='<div class="rail-err">加载失败：'+blEsc(e)+'</div>'; return; }
  if(!data || data.error){ list.innerHTML='<div class="rail-err">'+(data?blEsc(data.error):'无数据')+'</div>'; return; }
  STARTUP_DATA=data;
  const crb=document.getElementById('collabRulesBody'), crbBox=document.getElementById('collabRules');
  if(crb&&crbBox){ if(data.collab_prompt){ crb.textContent=data.collab_prompt; crbBox.style.display='block'; } else { crbBox.style.display='none'; } }
  const crbBtn=document.getElementById('collabRulesCopy');
  if(crbBtn) crbBtn.onclick=()=>copyText(document.getElementById('collabRulesBody').textContent, crbBtn);
  let h='';
  (data.windows||[]).forEach((w,i)=>{
    h+='<button type="button" class="rail-row" data-i="'+i+'" title="点选复制「'+blEsc(w.name)+'」口令">'
      +'<span class="rail-name">'+blEsc(w.name)+'</span>'
      +'<span class="rail-sig">'+blEsc(w.signature)+'</span>'
      +'<span class="rail-copy">📋</span></button>';
  });
  if(data.template){
    h+='<button type="button" class="rail-row tpl" data-tpl="1" title="点选复制通用模板">'
      +'<span class="rail-name">通用模板</span>'
      +'<span class="rail-sig">未单列窗口</span>'
      +'<span class="rail-copy">📋</span></button>';
  }
  list.innerHTML=h;
  list.querySelectorAll('.rail-row').forEach(r=>{
    r.onclick=()=>{
      const txt = r.dataset.tpl ? (STARTUP_DATA.template||'') : ((STARTUP_DATA.windows[+r.dataset.i].command)||STARTUP_DATA.template||'');
      copyText(txt, r.querySelector('.rail-copy'));
      r.classList.add('copied'); setTimeout(()=>r.classList.remove('copied'),1200);
      // 协同提示词固定显示在栏内预览区（无需滑出）
      const pv=document.getElementById('startupPrompt'), pb=document.getElementById('startupPromptBody');
      if(pv&&pb){ pb.textContent=txt; pv.style.display='block'; }
    };
  });
}
// ===================== 经验库（增强检索：标签云 + 角色/模块/BUG 分面过滤） =====================
let EXP_ITEMS=[], EXP_FACETS={roles:[],modules:[],bugs:[],tags:[],grades:[]};
let EXP_ACTIVE={roles:new Set(),modules:new Set(),bugs:new Set(),tags:new Set(),grades:new Set()};
let EXP_TAG_MAX=1, EXP_TAG_MIN=1, EXP_TAG_CNT={};
async function expLoad(){
  const r=await A('GET','/api/experience');
  const box=document.getElementById('expList');
  if(!r || !r.ok){ box.innerHTML='<div class="item">加载失败：'+(r&&r.error||'未知')+'</div>'; return; }
  const k=r.knowledge||{};
  EXP_ITEMS=[];
  (k.refs||[]).forEach(x=>EXP_ITEMS.push({type:'文档', path:x.path, title:x.title, group:x.group||'core', tags:x.tags||[], roles:x.roles||[], modules:x.modules||[], bugs:x.bugs||[], grade:x.grade||''}));
  (k.patterns||[]).forEach(x=>EXP_ITEMS.push({type:'可复用', path:'', title:x.text, group:'core', tags:[], roles:x.roles||[], modules:x.modules||[], bugs:x.bugs||[]}));
  (k.mistakes||[]).forEach(x=>EXP_ITEMS.push({type:'踩坑', path:'', title:x.text, group:'core', tags:[], roles:x.roles||[], modules:x.modules||[], bugs:x.bugs||[]}));
  EXP_FACETS=k.facets||{roles:[],modules:[],bugs:[],tags:[],grades:[]};
  EXP_TAG_CNT={}; (EXP_FACETS.tags||[]).forEach(([t,c])=>{ EXP_TAG_CNT[t]=c; });
  const cs=EXP_FACETS.tags.map(([,c])=>c); EXP_TAG_MAX=Math.max(1,...cs); EXP_TAG_MIN=Math.min(...cs,1);
  const nnEl=document.getElementById('expNoticeN'); if(nnEl) nnEl.textContent=EXP_ITEMS.filter(i=>i.group==='notice').length;
  EXP_ACTIVE={roles:new Set(),modules:new Set(),bugs:new Set(),tags:new Set(),grades:new Set()};
  const cb=document.getElementById('expNotice'); if(cb) cb.checked=false;
  expRenderFacets();
  expRender();
}
function expTitle(p){ const m=String(p).split('/'); return m[m.length-1].replace(/\.md$/,'')||p; }
// 标签云 + 分面按钮（点击切换激活；组内 OR、组间 AND）
function expChip(label, grp){
  const a=EXP_ACTIVE[grp].has(label)?' active':'';
  let style='';
  if(grp==='tags'){ const c=EXP_TAG_CNT[label]||1; const fs=12+Math.round(((c-EXP_TAG_MIN)/Math.max(1,EXP_TAG_MAX-EXP_TAG_MIN))*10); style=' style="font-size:'+fs+'px"'; }
  return '<span class="fchip'+a+'" data-grp="'+grp+'" data-label="'+blEsc(label)+'" onclick="expToggleFacet(this)"'+style+'>'+blEsc(label)+'</span>';
}
function expRenderFacets(){
  const box=document.getElementById('expFacets'); if(!box) return;
  const t=EXP_FACETS.tags||[];
  let h='';
  h+='<div class="frow"><span class="flabel">标签</span>'+(t.length?t.map(([x])=>expChip(x,'tags')).join(''):'<span class="muted">—</span>')+'</div>';
  if(EXP_FACETS.roles.length) h+='<div class="frow"><span class="flabel">角色</span>'+EXP_FACETS.roles.map(r=>expChip(r,'roles')).join('')+'</div>';
  if(EXP_FACETS.modules.length) h+='<div class="frow"><span class="flabel">模块</span>'+EXP_FACETS.modules.map(m=>expChip(m,'modules')).join('')+'</div>';
  if(EXP_FACETS.bugs.length) h+='<div class="frow"><span class="flabel">BUG</span>'+EXP_FACETS.bugs.map(b=>expChip(b,'bugs')).join('')+'</div>';
  if(EXP_FACETS.grades && EXP_FACETS.grades.length){
    const GL={E1:'E1 项目经验',E2:'E2 模块经验',E3:'E3 工程经验',E4:'E4 平台能力'};
    h+='<div class="frow"><span class="flabel">等级</span>'+EXP_FACETS.grades.map(g=>{
      const a=EXP_ACTIVE.grades.has(g)?' active':'';
      return '<span class="fchip'+a+'" data-grp="grades" data-label="'+g+'" onclick="expToggleFacet(this)">'+blEsc(GL[g]||g)+'</span>';
    }).join('')+'</div>';
  }
  const any=EXP_ACTIVE.roles.size||EXP_ACTIVE.modules.size||EXP_ACTIVE.bugs.size||EXP_ACTIVE.tags.size||EXP_ACTIVE.grades.size;
  if(any) h+='<div class="frow"><button class="fclear" onclick="expClearFacets()">✕ 清除筛选</button></div>';
  box.innerHTML=h;
}
function expToggleFacet(el){ const g=el.dataset.grp,l=el.dataset.label; if(EXP_ACTIVE[g].has(l))EXP_ACTIVE[g].delete(l); else EXP_ACTIVE[g].add(l); expRenderFacets(); expRender(); }
function expClearFacets(){ EXP_ACTIVE={roles:new Set(),modules:new Set(),bugs:new Set(),tags:new Set(),grades:new Set()}; expRenderFacets(); expRender(); }
function expMatch(it){
  const q=(document.getElementById('expSearch').value||'').toLowerCase();
  if(q){ const hay=(it.title+' '+(it.tags||[]).join(' ')+(it.roles||[]).join(' ')+(it.modules||[]).join(' ')+(it.bugs||[]).join(' ')+(it.path||'')).toLowerCase(); if(!hay.includes(q)) return false; }
  if(EXP_ACTIVE.tags.size && !(it.tags||[]).some(t=>EXP_ACTIVE.tags.has(t))) return false;
  if(EXP_ACTIVE.roles.size && !(it.roles||[]).some(r=>EXP_ACTIVE.roles.has(r))) return false;
  if(EXP_ACTIVE.modules.size && !(it.modules||[]).some(m=>EXP_ACTIVE.modules.has(m))) return false;
  if(EXP_ACTIVE.bugs.size && !(it.bugs||[]).some(b=>EXP_ACTIVE.bugs.has(b))) return false;
  if(EXP_ACTIVE.grades.size && !(it.grade||'').split(',').some(g=>EXP_ACTIVE.grades.has(g))) return false;
  return true;
}
function expRender(){
  const showNotice=document.getElementById('expNotice') && document.getElementById('expNotice').checked;
  const box=document.getElementById('expList');
  const list=EXP_ITEMS.filter(it=>{
    if(it.group==='notice' && !showNotice) return false;
    return expMatch(it);
  });
  window._expFiltered=list;
  box.innerHTML=list.map((it,i)=>{
    const metaParts=[...(it.roles||[]),...(it.modules||[]),...(it.bugs||[])];
    if(it.grade) metaParts.push('等级:'+it.grade);
    const meta=metaParts.map(x=>'<span class="mini">'+blEsc(x)+'</span>').join(' ');
    return '<div class="item" data-i="'+i+'" onclick="expOpen('+i+')">['+it.type+'] '+blEsc(it.title)+(meta?'<div class="imeta">'+meta+'</div>':'')+'</div>';
  }).join('') || '<div class="item">无匹配</div>';
}
function expFilter(){ expRender(); }
async function expOpen(i){
  const list=window._expFiltered||EXP_ITEMS;
  const it=list[i]; if(!it) return;
  const view=document.getElementById('expView');
  const metaParts=[...(it.roles||[]),...(it.modules||[]),...(it.bugs||[])];
  if(it.grade) metaParts.push('等级:'+it.grade);
  const metaHtml=metaParts.length?'<div class="refmeta">'+metaParts.map(x=>'<span class="mini">'+blEsc(x)+'</span>').join(' ')+'</div>':'';
  if(it.type==='文档' && it.path){
    const r=await A('GET','/api/experience/doc?path='+encodeURIComponent(it.path));
    if(r && r.ok){ view.innerHTML=metaHtml+expMd(r.text); }
    else { view.innerHTML='<div class="status bad">读取失败：'+(r&&r.error||'未知')+'</div>'; }
  } else {
    view.innerHTML=metaHtml+'<div class="refbox">'+blEsc(it.title)+'</div>';
  }
}
// 轻量 markdown → 安全 HTML（先转义，再处理 # 标题 / **粗体** / `代码` / - 列表 / 引用 / 表格行）
function expMd(src){
  const lines=String(src).replace(/\r\n/g,'\n').split('\n');
  let html=''; let inList=false; let para=[];
  const flushP=()=>{ if(para.length){ html+='<p>'+expInline(para.join(' '))+'</p>'; para=[]; } };
  const flushL=()=>{ if(inList){ html+='</ul>'; inList=false; } };
  for(const ln of lines){
    const s=ln.trim();
    if(s===''){ flushP(); flushL(); continue; }
    let m;
    if(m=s.match(/^######\s+(.*)/)){ flushP(); flushL(); html+='<h6>'+expInline(m[1])+'</h6>'; }
    else if(m=s.match(/^#####\s+(.*)/)){ flushP(); flushL(); html+='<h5>'+expInline(m[1])+'</h5>'; }
    else if(m=s.match(/^####\s+(.*)/)){ flushP(); flushL(); html+='<h4>'+expInline(m[1])+'</h4>'; }
    else if(m=s.match(/^###\s+(.*)/)){ flushP(); flushL(); html+='<h3>'+expInline(m[1])+'</h3>'; }
    else if(m=s.match(/^##\s+(.*)/)){ flushP(); flushL(); html+='<h2>'+expInline(m[1])+'</h2>'; }
    else if(m=s.match(/^#\s+(.*)/)){ flushP(); flushL(); html+='<h1>'+expInline(m[1])+'</h1>'; }
    else if(m=s.match(/^[-*]\s+(.*)/)){ flushP(); if(!inList){ html+='<ul>'; inList=true; } html+='<li>'+expInline(m[1])+'</li>'; }
    else if(m=s.match(/^>\s+(.*)/)){ flushP(); flushL(); html+='<blockquote>'+expInline(m[1])+'</blockquote>'; }
    else if(m=s.match(/^\|(.+)\|$/)){ flushP(); flushL(); html+='<div class="refbox">'+blEsc(s)+'</div>'; }
    else { para.push(s); }
  }
  flushP(); flushL();
  return html;
}
function expInline(t){
  let h=blEsc(t);
  h=h.replace(/\*\*(.+?)\*\*/g,'<b>$1</b>');
  h=h.replace(/`(.+?)`/g,'<code>$1</code>');
  return h;
}

// ===================== 双闸门平台化验证（PM 不装 Godot 也能卡质量） =====================
let _gateAuto=false;
async function gateRun(){
  const btn=document.getElementById('gateRunBtn'), st=document.getElementById('gateStatus'), v=document.getElementById('gateView');
  btn.disabled=true; st.textContent='验证中（调起 Godot headless，约 10~40 秒）…'; st.className='status';
  v.innerHTML='<div class="status">正在运行 GATE1 + GATE2，请稍候…</div>';
  let data;
  try{ data=await A('GET','/api/gate/run'); }
  catch(e){ btn.disabled=false; st.textContent='请求失败'; st.className='status bad'; v.innerHTML='<div class="status bad">'+blEsc(e)+'</div>'; return; }
  btn.disabled=false;
  if(!data || !data.ok){ st.textContent='无法运行'; st.className='status bad'; v.innerHTML='<div class="status bad">'+(data?blEsc(data.error):'无数据')+'</div>'; return; }
  const g1=data.gate1, g2=data.gate2, ok=data.green;
  st.textContent= ok?'✅ 双闸门全绿（可提交）':'🔴 红门禁（禁止提交）';
  st.className='status '+(ok?'ok':'bad');
  let h='<div style="margin:8px 0">';
  h+='<div>Godot：<code>'+blEsc(data.godot)+'</code></div>';
  h+='<div style="margin-top:6px">GATE1（headless 零错误）： <span class="status '+(g1.green?'ok':'bad')+'">'+(g1.green?'绿':'红')+'</span> · ERROR 数 '+g1.errors+(g1.sample&&g1.sample.length?'<pre style="white-space:pre-wrap;max-height:160px;overflow:auto;margin:4px 0">'+blEsc(g1.sample.join("\n"))+'</pre>':'')+'</div>';
  h+='<div style="margin-top:6px">GATE2（run_all 零 ✗）： <span class="status '+(g2.green?'ok':'bad')+'">'+(g2.green?'绿':'红')+'</span> · 套件通过 '+g2.suites+' · 失败 '+g2.failed+' · ✗ '+g2.xfail+'</div>';
  h+='</div>';
  h+= ok
    ? '<div class="status ok" style="margin-top:8px">✅ 门禁全绿，可窗口署名提交并推 Gitee。</div>'
    : '<div class="status bad" style="margin-top:8px">⛔ 红门禁：存在报错/失败/✗，须立即修红再提交；切勿为过门禁去动无关模块（那才是真绕远路）。</div>';
  v.innerHTML=h;
}
async function gateLoad(){ if(!_gateAuto){ _gateAuto=true; gateRun(); } }

// ===================== L3 任务总控（任务驱动：知识路由 + 双闸门 + 变更闭环） =====================
let _orcAuto=false, _orcRelated=[];
async function orcRun(){
  const task=document.getElementById('orcTask').value.trim();
  const v=document.getElementById('orcView');
  if(!task){ v.innerHTML='<div class="status bad">请先填写任务描述</div>'; return; }
  v.innerHTML='<div class="status">正在做知识路由（匹配经验库分面）…</div>';
  let d;
  try{ d=await A('GET','/api/orchestrate?task='+encodeURIComponent(task)); }
  catch(e){ v.innerHTML='<div class="status bad">请求失败：'+blEsc(e)+'</div>'; return; }
  if(!d || !d.ok){ v.innerHTML='<div class="status bad">'+(d?blEsc(d.error):'无数据')+'</div>'; return; }
  _orcRelated=d.related||[];
  let h='<div style="margin:6px 0">';
  h+='<div><b>识别角色：</b>'+(d.matched_roles.length?d.matched_roles.map(r=>'<span class="fchip">'+blEsc(r)+'</span>').join(' '):'<span class="muted">（未命中，任务词可更具体）</span>')+'</div>';
  h+='<div style="margin-top:4px"><b>识别模块：</b>'+(d.matched_modules.length?d.matched_modules.map(m=>'<span class="fchip">'+blEsc(m)+'</span>').join(' '):'<span class="muted">（未命中）</span>')+'</div>';
  if(d.matched_bugs.length) h+='<div style="margin-top:4px"><b>命中 BUG：</b>'+d.matched_bugs.map(b=>'<span class="fchip bad">'+blEsc(b)+'</span>').join(' ')+'</div>';
  h+='</div>';
  h+='<div style="margin:10px 0 4px"><b>相关经验（'+_orcRelated.length+' 篇，点开可读全文）：</b></div>';
  h+='<div id="orcList">'+(_orcRelated.map((r,i)=>'<div class="item" onclick="orcOpen('+i+')">📄 '+blEsc(r.title)+(r.roles&&r.roles.length?' <span class="mini">'+r.roles.join('/')+'</span>':'')+(r.modules&&r.modules.length?' <span class="mini">'+r.modules.join('/')+'</span>':'')+'</div>').join('')||'<div class="item">无匹配</div>')+'</div>';
  h+='<div class="row" style="margin-top:14px;border-top:1px solid var(--line);padding-top:10px">';
  h+='<button onclick="orcGate()" style="background:var(--accent);color:#fff;border:none;padding:8px 14px;border-radius:6px;cursor:pointer">🔧 跑双闸门门禁</button>';
  h+='<button onclick="orcShowChangelog()" style="margin-left:8px;border:1px solid var(--line);background:transparent;color:var(--txt);padding:8px 14px;border-radius:6px;cursor:pointer">📝 登记变更</button>';
  h+='</div><div id="orcGateView" style="margin-top:8px"></div>';
  h+='<div id="orcClView" style="margin-top:8px;display:none">'+_orcChangelogForm()+'</div>';
  v.innerHTML=h;
}
async function orcOpen(i){
  const r=_orcRelated[i]; if(!r) return;
  const v=document.getElementById('orcView');
  const d=await A('GET','/api/experience/doc?path='+encodeURIComponent(r.path));
  if(d && d.ok){ v.innerHTML='<div class="refbox" style="margin-bottom:8px"><b>'+blEsc(r.title)+'</b> '+(r.roles||[]).map(x=>'<span class="mini">'+blEsc(x)+'</span>').join(' ')+(r.bugs||[]).map(x=>'<span class="mini bad">'+blEsc(x)+'</span>').join(' ')+'</div>'+expMd(d.text); }
  else { v.innerHTML='<div class="status bad">读取失败：'+(d&&d.error||'未知')+'</div>'; }
}
async function orcGate(){
  const btn=document.getElementById('orcGateView'); btn.innerHTML='<div class="status">调起 Godot headless 验证中…</div>';
  const d=await A('GET','/api/gate/run');
  if(!d||!d.ok){ btn.innerHTML='<div class="status bad">无法运行：'+(d&&d.error||'')+'</div>'; return; }
  const ok=d.green;
  btn.innerHTML='<div class="status '+(ok?'ok':'bad')+'">'+(ok?'✅ 双闸门全绿（可提交）':'🔴 红门禁（禁止提交）：GATE1 错误 '+d.gate1.errors+' / GATE2 失败 '+d.gate2.failed+' / ✗ '+d.gate2.xfail)+'</div>';
}
function _orcChangelogForm(){
  return '<div style="margin-top:8px"><div class="row" style="margin:6px 0"><input id="orcClModule" placeholder="模块（必填，如 CombatScene）" style="flex:1"></div>'
    +'<div class="row" style="margin:6px 0"><input id="orcClScope" placeholder="改动范围（如 scenes/gameplay/battle）" style="flex:1"></div>'
    +'<div class="row" style="margin:6px 0"><input id="orcClWhat" placeholder="改了什么（必填）" style="flex:1"></div>'
    +'<div class="row" style="margin:6px 0"><input id="orcClImpact" placeholder="影响/风险" style="flex:1"></div>'
    +'<div class="row" style="margin:6px 0"><input id="orcClRef" placeholder="关联（BUG-xx / 派单 / commit）" style="flex:1"></div>'
    +'<div class="row" style="margin:6px 0"><input id="orcClCommit" placeholder="commit（可选，提交后补）" style="flex:1"></div>'
    +'<button onclick="orcChangelog()" style="background:var(--accent);color:#fff;border:none;padding:8px 14px;border-radius:6px;cursor:pointer;margin-top:4px">✅ 登记到更改日志</button>'
    +' <span id="orcClMsg" class="status" style="margin-left:8px"></span></div>';
}
function orcShowChangelog(){ const e=document.getElementById('orcClView'); e.style.display = e.style.display==='none'?'block':'none'; }
async function orcChangelog(){
  const module=document.getElementById('orcClModule').value.trim();
  const what=document.getElementById('orcClWhat').value.trim();
  if(!module||!what){ show('orcClMsg','module 与 what 必填',false); return; }
  const d=await A('POST','/api/changelog',{module,scope:document.getElementById('orcClScope').value.trim(),
    what,impact:document.getElementById('orcClImpact').value.trim(),ref:document.getElementById('orcClRef').value.trim(),
    commit:document.getElementById('orcClCommit').value.trim()});
  if(d&&d.ok){ show('orcClMsg','✅ 已登记',true); }
  else { show('orcClMsg','失败：'+(d&&d.error||''),false); }
}
async function orcLoad(){ if(!_orcAuto){ _orcAuto=true; } }
// L1 自动依赖图：扫描五层架构依赖，标注「向上依赖违例」（违反架构铁律）
async function orcDeps(){
  const v=document.getElementById('orcDepsView');
  v.innerHTML='<div class="status">扫描 .gd 依赖图（五层架构）中…</div>';
  let d;
  try{ d=await A('GET','/api/deps'); }
  catch(e){ v.innerHTML='<div class="status bad">请求失败：'+blEsc(e)+'</div>'; return; }
  if(!d||!d.ok){ v.innerHTML='<div class="status bad">'+(d?blEsc(d.error):'无数据')+'</div>'; return; }
  const s=d.summary||{};
  let h='<div class="hint">🕸 依赖图（L1 · 结构认知）：扫描工程内全部 .gd，按五层架构（core < data < services < autoload < scenes < resources/tests/tools）标注「向上依赖违例」。架构铁律：只允许上层依赖更基础的层。</div>';
  // 摘要
  h+='<div style="margin:8px 0;display:flex;flex-wrap:wrap;gap:8px">';
  h+='<span class="fchip">.gd 文件 '+ (s.gd_files||0) +'</span>';
  h+='<span class="fchip">依赖边 '+ (s.edges||0) +'（解析 '+(s.resolved_edges||0)+'/未解析 '+(s.unresolved_refs||0)+'）</span>';
  h+='<span class="fchip '+( (s.upward_violations||0)?'bad':'ok')+'">向上依赖违例 '+(s.upward_violations||0)+'</span>';
  h+='</div>';
  // 各层分布
  if(s.layers){ h+='<div style="margin:4px 0"><b>各层文件分布：</b>'+Object.keys(s.layers).map(k=>'<span class="mini">'+blEsc(k)+' '+s.layers[k]+'</span>').join(' ')+'</div>'; }
  // 违例清单
  const vs=d.violations||[];
  h+='<div style="margin:10px 0 4px"><b>⚠ 向上依赖违例（'+vs.length+' 条，须走 EventBus/解耦修复）：</b></div>';
  if(vs.length){
    h+='<div>'+vs.map(v=>'<div class="item" style="border-left:3px solid var(--bad, #c44)">'+blEsc(v.from_layer)+' → '+blEsc(v.to_layer)+' ｜ '+blEsc(v.from)+' <span class="mini">'+blEsc(v.kind)+'</span> ⇒ '+blEsc(v.to)+'</div>').join('')+'</div>';
  } else {
    h+='<div class="status ok">✅ 无向上依赖违例（架构健康）</div>';
  }
  // 未解析引用（点到为止，最多 30）
  const ur=d.unresolved_refs||[];
  if(ur.length){
    h+='<details style="margin-top:10px"><summary class="mini">未解析引用 '+(ur.length)+' 条（缺文件/拼写，非层违例，点开）</summary>';
    h+='<div style="margin-top:6px">'+(ur.slice(0,30).map(u=>'<div class="mini">'+blEsc(u)+'</div>').join(''))+(ur.length>30?'<div class="mini">…仅显示前 30</div>':'')+'</div></details>';
  }
  v.innerHTML=h;
}

stat();npcLoad();loadingLoad();backlogLoad();loadStartupCard();uiSkinLoad();_startBacklogAutoRefresh();logLoad();_startOpLogAutoRefresh();
