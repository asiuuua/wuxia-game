/* ============ 任务流程图（T2 可视化节点画布） ============ */
let qgCur=null, qgList=[], qgSelNode=null;
const qgTypeColor={start:'#34d399',dialog:'#7c9cff',choice:'#f0b036',battle:'#ef6a6a',give_item:'#b47cff',flag_set:'#36c5c5',flag_check:'#e879f9',goal:'#9ce08f',end:'#e2e8f0'};
const qgTypeName={start:'开始',dialog:'对话',choice:'选择',battle:'战斗',give_item:'给物品',flag_set:'设标记',flag_check:'判断标记',goal:'目标',end:'结局'};
const qgNodeName=(nd,key)=>((nd&&nd.label)||(nd&&nd.text)||key||'?');
const qgEsc=x=>String(x==null?'':x).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');

function qgLoad(){
  A('GET','/api/quest_graph').then(r=>{
    qgList=(r&&r.quests)||[];
    const sel=document.getElementById('qgSel'); sel.innerHTML='';
    qgList.forEach(q=>{const o=document.createElement('option');o.value=q.id;o.textContent='('+q.region+') '+q.name+' ['+q.node_count+'节点]';o._data=q;sel.appendChild(o);});
    sel.onchange=()=>{const s=sel.selectedOptions[0];qgRender(s?s._data:null);};
    const s=sel.selectedOptions[0]; qgRender(s?s._data:null);
  }).catch(()=>show('qgStat','读取任务图失败',false));
}
function qgView(){ return {region:qgCur.region,id:qgCur.id,name:qgCur.name,nodes:qgCur.graph.nodes,start_node:qgCur.graph.start_node,endings:qgCur.graph.endings}; }
function qgRender(q){
  const cvs=document.getElementById('qgCanvas'); cvs.innerHTML='';
  qgSelNode=null;
  if(!q){ qgCur=null; document.getElementById('qgNid').value='';document.getElementById('qgForm').innerHTML='';document.getElementById('qgInspEmpty').style.display='';return; }
  qgCur={region:q.region,id:q.id,name:q.name,graph:{nodes:q.nodes||{},start_node:q.start_node||'',endings:q.endings||[]}};
  const nodes=qgCur.graph.nodes;
  const ids=Object.keys(nodes);
  const cols=Math.max(1,Math.ceil(Math.sqrt(ids.length)));
  ids.forEach((k,i)=>{ if(!nodes[k]||typeof nodes[k]!=='object')nodes[k]={type:'dialog'}; if(!nodes[k]._vis||typeof nodes[k]._vis!=='object')nodes[k]._vis={x:(i%cols)*220+40,y:Math.floor(i/cols)*130+40}; });
  ids.forEach(k=>_qgNodeEl(nodes,k,cvs));
  _qgDrawEdges(nodes,cvs);
  show('qgStat','已加载 '+q.name+'（'+ids.length+' 节点）',true);
}
function _qgNodeEl(nodes,key,cvs){
  const nd=nodes[key]; const color=qgTypeColor[nd.type]||'#94a3b8';
  const div=document.createElement('div');
  div.className='qgn'; div.id='qgn_'+key; div.dataset.id=key;
  div.style.cssText='position:absolute;left:'+nd._vis.x+'px;top:'+nd._vis.y+'px;width:150px;padding:6px 10px;border:1px solid '+color+';border-left:4px solid '+color+';border-radius:8px;background:var(--panel2);cursor:move;z-index:1;box-shadow:0 1px 4px #000a;user-select:none';
  const name=qgNodeName(nd,key);
  div.innerHTML='<div style="font-size:10px;color:'+color+';font-weight:700">'+qgEsc(qgTypeName[nd.type]||nd.type||'?')+'</div>'+
    '<div style="font-size:12px;margin-top:2px;font-weight:600;word-break:break-all">'+qgEsc(name)+'</div>'+
    (name!==key?'<div style="font-size:9px;color:var(--muted);margin-top:1px;word-break:break-all">'+qgEsc(key)+'</div>':'');
  cvs.appendChild(div);
  _qgDrag(div,key,cvs);
}
function _qgGeo(key){ const el=document.getElementById('qgn_'+key); if(!el)return null; return {x:el.offsetLeft+66,y:el.offsetTop+el.offsetHeight/2}; }
function qgEdgeDescs(sid,n){
  const nodes=qgCur.graph.nodes; const out=[];
  const add=(to,l,c)=>{ if(to&&nodes[to])out.push({from:sid,to,l:l||'',c:c||'#7c9cff'}); };
  if(n&&typeof n==='object'){
    if(n.next)add(n.next,'下一步','#7c9cff');
    if(n.on_win_next)add(n.on_win_next,'胜利','#34d399');
    if(n.on_lose_next)add(n.on_lose_next,'失败','#ef6a6a');
    (n.options||[]).forEach(o=>{ if(o&&typeof o==='object'&&o.jump_id){ let l='☞'+(o.text||'').slice(0,8); if(o.cond)l+=(o.cond.kind==='favor'?(' 好感≥'+o.cond.arg):(' flag:'+o.cond.arg)); add(o.jump_id,l,'#f0b036'); } });
  }
  return out;
}
function _qgDrawEdges(nodes,cvs){
  const edges=[];
  Object.keys(nodes).forEach(s=>{ const n=nodes[s]; if(typeof n==='object')qgEdgeDescs(s,n).forEach(e=>edges.push(e)); });
  let W=500,H=400;
  Object.keys(nodes).forEach(k=>{ const v=nodes[k]._vis; if(v&&v.x>W)W=v.x; if(v&&v.y>H)H=v.y; });
  W+=240; H+=180;
  const old=document.getElementById('qgSvg'); if(old)old.parentNode.removeChild(old);
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.id='qgSvg'; svg.setAttribute('width',W); svg.setAttribute('height',H);
  svg.style.cssText='position:absolute;left:0;top:0;overflow:visible;pointer-events:none;z-index:0';
  let body='<defs><marker id="qgArr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0L10,5L0,10z" fill="#8fb4ff"/></marker></defs>';
  edges.forEach(e=>{
    const a=_qgGeo(e.from), b=_qgGeo(e.to); if(!a||!b)return;
    const dx=b.x-a.x,dy=b.y-a.y,len=Math.hypot(dx,dy)||1,mx=a.x+dx/2,my=a.y+dy/2-6;
    body+='<line x1="'+a.x+'" y1="'+a.y+'" x2="'+b.x+'" y2="'+b.y+'" stroke="'+e.c+'" stroke-width="2" marker-end="url(#qgArr)"/>';
    body+='<text x="'+mx+'" y="'+my+'" font-size="11" fill="'+e.c+'" text-anchor="middle" paint-order="stroke" stroke="#0a0f1c" stroke-width="3" stroke-linejoin="round">'+qgEsc(e.l)+'</text>';
  });
  svg.innerHTML=body; cvs.appendChild(svg);
}
function _qgDrag(div,key,cvs){
  let sx=0,sy=0,ox=0,oy=0,drag=false;
  div.addEventListener('pointerdown',e=>{ e.preventDefault(); drag=true; sx=e.clientX; sy=e.clientY; ox=div.offsetLeft; oy=div.offsetTop; _qgSelectNode(key);
    const mv=ev=>{ if(!drag)return; div.style.left=(ox+ev.clientX-sx)+'px'; div.style.top=(oy+ev.clientY-sy)+'px'; _qgDrawEdges(qgCur.graph.nodes,cvs); };
    const up=()=>{ drag=false; qgSelNode=key; qgCur.graph.nodes[key]._vis={x:parseFloat(div.style.left),y:parseFloat(div.style.top)}; document.removeEventListener('pointermove',mv); document.removeEventListener('pointerup',up); };
    document.addEventListener('pointermove',mv); document.addEventListener('pointerup',up);
  });
}
function _qgSelectNode(key){
  qgSelNode=key;
  document.querySelectorAll('.qgn').forEach(el=>{ el.style.outline = (el.dataset.id===key)?'2px solid var(--accent,#7c9cff)':'none'; });
  const nd=qgCur.graph.nodes[key];
  document.getElementById('qgInspEmpty').style.display='none';
  document.getElementById('qgNid').value=key;
  qgFormRender(nd,key);
  const names=Object.keys(qgCur.graph.nodes), inc=names.filter(s=>s!==key&&qgEdgeDescs(s,qgCur.graph.nodes[s]).some(e=>e.to===key));
  const outb=qgEdgeDescs(key,nd).map(e=>e.to);
  document.getElementById('qgRef').innerHTML='<b>谁连着它：</b>'+(inc.map(i=>qgNodeName(qgCur.graph.nodes[i],i)).join('、')||'无')+'<br><b>它连着谁：</b>'+(outb.map(o=>qgNodeName(qgCur.graph.nodes[o],o)).join('、')||'无');
}
/* ---- 无代码表单：点选类型/填中文名/下拉框链接下一节点 ---- */
function qgFormRender(nd,key){
  const f=document.getElementById('qgForm'); if(!f)return;
  const names=Object.keys(qgCur.graph.nodes);
  const opt=(cur,ph)=>'<option value="">'+ph+'</option>'+names.map(n=>'<option value="'+ste(n)+'"'+(cur===n?' selected':'')+'>'+ste(qgNodeName(qgCur.graph.nodes[n],n))+'</option>').join('');
  const t=nd.type||'dialog';
  const typeSel='<div class="story-line"><label>类型</label><select id="qf_type" onchange="qgFormTypeChange()">'+Object.keys(qgTypeName).map(tp=>'<option value="'+tp+'"'+(tp===t?' selected':'')+'>'+qgTypeName[tp]+'</option>').join('')+'</select></div>';
  const labelRow='<div class="story-line"><label>中文名</label><input id="qf_label" value="'+ste(nd.label||'')+'" placeholder="例如：失剑案开场"></div>';
  let h=typeSel+labelRow;
  if(t==='dialog'||t==='goal'){
    h+='<div class="story-line" style="flex-direction:column;align-items:stretch"><label>内容</label><textarea id="qf_text" rows="3" placeholder="这段剧情说什么">'+ste(nd.text||'')+'</textarea></div>';
    h+='<div class="story-line"><label>下一节点</label><select id="qf_next">'+opt(nd.next||'','（到这里结束）')+'</select></div>';
  }else if(t==='choice'){
    h+='<div class="hint" style="margin:2px 0 4px">玩家在这里做选择，每个选项连到不同走向：</div><div id="qf_opts">';
    (nd.options||[]).forEach((o,i)=>{ h+=qgOptRowHtml(o,i,names); });
    h+='</div><button class="act sec" type="button" onclick="qgOptAdd()">＋ 加一个选项</button>';
  }else if(t==='battle'){
    h+='<div class="story-line"><label>战斗id</label><input id="qf_battle" value="'+ste(nd.battle_id||'')+'" placeholder="battle_xxx"></div>';
    h+='<div class="story-line"><label>胜利→</label><select id="qf_win">'+opt(nd.on_win_next||'','（到这里结束）')+'</select></div>';
    h+='<div class="story-line"><label>失败→</label><select id="qf_lose">'+opt(nd.on_lose_next||'','（到这里结束）')+'</select></div>';
  }else if(t==='give_item'){
    h+='<div class="story-line"><label>物品id</label><input id="qf_item" value="'+ste(nd.item_id||'')+'" placeholder="item_xxx"></div>';
    h+='<div class="story-line"><label>数量</label><input id="qf_count" type="number" value="'+(nd.count!=null?nd.count:1)+'"></div>';
    h+='<div class="story-line"><label>下一节点</label><select id="qf_next">'+opt(nd.next||'','（到这里结束）')+'</select></div>';
  }else if(t==='flag_set'){
    h+='<div class="story-line"><label>标记名</label><input id="qf_flag" value="'+ste(nd.flag||'')+'" placeholder="如 quest_done"></div>';
    h+='<div class="story-line"><label>值</label><input id="qf_fval" value="'+ste(nd.value!=null?nd.value:'')+'"></div>';
    h+='<div class="story-line"><label>下一节点</label><select id="qf_next">'+opt(nd.next||'','（到这里结束）')+'</select></div>';
  }else if(t==='flag_check'){
    h+='<div class="story-line"><label>标记名</label><input id="qf_flag" value="'+ste(nd.flag||'')+'" placeholder="如 quest_done"></div>';
    h+='<div class="story-line"><label>值</label><input id="qf_fval" value="'+ste(nd.value!=null?nd.value:'')+'"></div>';
    h+='<div class="story-line"><label>成立→</label><select id="qf_yes">'+opt(nd.on_yes_next||nd.next||'','（到这里结束）')+'</select></div>';
    h+='<div class="story-line"><label>不成立→</label><select id="qf_no">'+opt(nd.on_no_next||'','（到这里结束）')+'</select></div>';
  }else if(t==='end'){
    h+='<div class="story-line"><label>结局名</label><input id="qf_text" value="'+ste(nd.text||nd.label||'')+'" placeholder="如：找回失剑（好结局）"></div>';
  }
  f.innerHTML=h;
}
function qgOptRowHtml(o,i,names){
  o=o||{};
  return '<div class="opt-row" style="margin-bottom:4px">'+
    '<input class="qfo_text" placeholder="选项文字" value="'+ste(o.text||'')+'" style="flex:2">'+
    '<select class="qfo_jump" style="flex:1"><option value="">（到这里结束）</option>'+names.map(n=>'<option value="'+ste(n)+'"'+(o.jump_id===n?' selected':'')+'>'+ste(qgNodeName(qgCur.graph.nodes[n],n))+'</option>').join('')+'</select>'+
    '<button class="act bad" type="button" style="flex:none" onclick="this.parentNode.remove()">✕</button></div>';
}
function qgOptAdd(){ const box=document.getElementById('qf_opts'); if(box)box.insertAdjacentHTML('beforeend',qgOptRowHtml({},-1,Object.keys(qgCur.graph.nodes))); }
function qgFormTypeChange(){ const t=document.getElementById('qf_type').value; const nd=qgCur.graph.nodes[qgSelNode]||{}; const label=document.getElementById('qf_label').value; qgFormRender(Object.assign({},nd,{type:t,label:label}),qgSelNode); }
function qgFormCollect(){
  const g=document.getElementById('qgForm'); if(!g)return null;
  const v=id=>{const e=document.getElementById(id);return e?e.value.trim():'';};
  const t=v('qf_type')||'dialog';
  const out={type:t};
  if(v('qf_label')!=='')out.label=v('qf_label');
  if(t==='dialog'||t==='goal'){
    if(v('qf_text')!=='')out.text=v('qf_text');
    if(v('qf_next'))out.next=v('qf_next');
  }else if(t==='choice'){
    const opts=[];
    g.querySelectorAll('.opt-row').forEach(r=>{
      const text=r.querySelector('.qfo_text').value.trim(), jump=r.querySelector('.qfo_jump').value;
      if(text||jump)opts.push({text:jump?text:'',jump_id:jump});
    });
    if(opts.length)out.options=opts;
  }else if(t==='battle'){
    if(v('qf_battle'))out.battle_id=v('qf_battle');
    if(v('qf_win'))out.on_win_next=v('qf_win');
    if(v('qf_lose'))out.on_lose_next=v('qf_lose');
  }else if(t==='give_item'){
    if(v('qf_item'))out.item_id=v('qf_item');
    out.count=parseInt(v('qf_count'),10)||1;
    if(v('qf_next'))out.next=v('qf_next');
  }else if(t==='flag_set'){
    if(v('qf_flag'))out.flag=v('qf_flag');
    if(v('qf_fval')!=='')out.value=v('qf_fval');
    if(v('qf_next'))out.next=v('qf_next');
  }else if(t==='flag_check'){
    if(v('qf_flag'))out.flag=v('qf_flag');
    if(v('qf_fval')!=='')out.value=v('qf_fval');
    if(v('qf_yes'))out.on_yes_next=v('qf_yes');
    if(v('qf_no'))out.on_no_next=v('qf_no');
  }else if(t==='end'){
    if(v('qf_text')!=='')out.text=v('qf_text');
  }
  return out;
}
function qgApplyNode(){
  if(!qgCur||!qgSelNode)return;
  const key=qgSelNode; const obj=qgFormCollect();
  if(!obj){ show('qgStat','表单读取失败',false); return; }
  const nid=document.getElementById('qgNid').value.trim()||key;
  obj._vis=qgCur.graph.nodes[key]._vis||{x:40,y:40};
  if(nid!==key){
    delete qgCur.graph.nodes[key];
    Object.keys(qgCur.graph.nodes).forEach(s=>{ const n=qgCur.graph.nodes[s]; if(typeof n==='object'){ const rep=v=>v===key?nid:v; if(typeof n.next==='string')n.next=rep(n.next); if(typeof n.on_win_next==='string')n.on_win_next=rep(n.on_win_next); if(typeof n.on_lose_next==='string')n.on_lose_next=rep(n.on_lose_next); (n.options||[]).forEach(o=>{ if(o&&typeof o==='object'&&o.jump_id===key)o.jump_id=nid; }); } });
    if(qgCur.graph.start_node===key)qgCur.graph.start_node=nid;
  }
  qgCur.graph.nodes[nid]=obj; show('qgStat','节点已应用（记得保存整图）',true); qgRender(qgView()); _qgSelectNode(nid);
}
function qgAddNode(){
  if(!qgCur){ show('qgStat','请先选择一张任务图',false); return; }
  const key='n_'+Date.now().toString(36);
  qgCur.graph.nodes[key]={type:'dialog',label:'新节点',text:'',next:''};
  show('qgStat','已新增节点，请编辑后保存整图',true); qgRender(qgView()); _qgSelectNode(key);
}
function qgDelNode(){
  if(!qgCur||!qgSelNode)return;
  const key=qgSelNode; const nodes=qgCur.graph.nodes; delete nodes[key];
  Object.keys(nodes).forEach(s=>{ const n=nodes[s]; if(typeof n==='object'){ if(n.next===key)n.next=''; if(n.on_win_next===key)n.on_win_next=''; if(n.on_lose_next===key)n.on_lose_next=''; if(Array.isArray(n.options))n.options=n.options.filter(o=>!o||o.jump_id!==key); } });
  if(qgCur.graph.start_node===key)qgCur.graph.start_node='';
  show('qgStat','已删除节点 '+key,true); qgRender(qgView());
}
async function qgSave(){
  if(!qgCur){ show('qgStat','没有可保存的任务图',false); return; }
  const r=await A('POST','/api/quest_graph/save',{region:qgCur.region,qid:qgCur.id,graph:qgCur.graph});
  show('qgStat',r.msg,!!r.ok);
}
/* ============ i18n 文案表（系统运维页签） ============ */
async function i18nLoad(){
  const box=document.getElementById('i18nList'); if(!box)return;
  let rows=[]; try{ rows=((await A('GET','/api/i18n'))||{}).rows||[]; }catch(e){ box.innerHTML='<div class="hint">文案表读取失败</div>'; return; }
  box.innerHTML='';
  if(!rows.length){ box.innerHTML='<div class="hint">strings.csv 尚无文案行</div>'; return; }
  rows.slice().reverse().forEach(k=>box.appendChild(i18nRow(k)));
}
function i18nRow(k){
  const r=document.createElement('div');
  r.style.cssText='display:grid;grid-template-columns:150px 1fr 1fr 1fr auto;gap:6px;align-items:center;background:var(--panel2);border:1px solid var(--line);border-radius:6px;padding:6px 8px';
  r.innerHTML='<span style="font-family:ui-monospace,monospace;font-size:12px;word-break:break-all;color:#7c9cff">'+iEsc(k.key)+'</span>'
    +'<input class="i18n-v" data-l="zh_CN" value="'+iEsc(k.zh_CN||'')+'">'
    +'<input class="i18n-v" data-l="zh_TW" value="'+iEsc(k.zh_TW||'')+'">'
    +'<input class="i18n-v" data-l="en" value="'+iEsc(k.en||'')+'">'
    +'<button class="act sec" type="button" onclick="i18nSaveRow(this,'+JSON.stringify(k.key)+')">存</button>';
  return r;
}
function i18nSaveRow(btn,key){
  const row=btn.parentNode;
  const v={}; row.querySelectorAll('.i18n-v').forEach(i=>v[i.dataset.l]=i.value);
  A('POST','/api/i18n',{key,zh_CN:v.zh_CN,zh_TW:v.zh_TW,en:v.en}).then(r=>show('i18nStat',r.msg,!!r.ok));
}
async function i18nSave(){
  const key=document.getElementById('i18nKey').value.trim();
  if(!key){ show('i18nStat','key 不能为空',false); return; }
  const r=await A('POST','/api/i18n',{key,zh_CN:document.getElementById('i18nZh').value,zh_TW:document.getElementById('i18nTw').value,en:document.getElementById('i18nEn').value});
  show('i18nStat',r.msg,!!r.ok);
  if(r.ok){ i18nLoad(); }
}
function iEsc(x){ return String(x==null?'':x).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
