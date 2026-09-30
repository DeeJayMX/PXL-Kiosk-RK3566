// Affiche le pilote GL réellement utilisé par le Chromium du kiosque (via WebGL).
// Attendu : « ANGLE (ARM, Mali-G52, OpenGL ES 3.2) ». « llvmpipe » ou « SwiftShader » = repli logiciel.
const tabs = await (await fetch("http://127.0.0.1:9222/json")).json();
const ws = new WebSocket(tabs.find(t=>t.type==="page").webSocketDebuggerUrl); await new Promise(r=>ws.onopen=r);
let id=0; const cmd=(m,p={})=>new Promise(r=>{const i=++id; ws.addEventListener("message",e=>{const x=JSON.parse(e.data); if(x.id===i) r(x)}); ws.send(JSON.stringify({id:i,method:m,params:p}))});
const r = await cmd("Runtime.evaluate",{expression:`(()=>{const g=document.createElement("canvas").getContext("webgl");const d=g&&g.getExtension("WEBGL_debug_renderer_info");return d?g.getParameter(d.UNMASKED_RENDERER_WEBGL):"pas de webgl"})()`,returnByValue:true});
console.log(r.result.result.value); ws.close();
