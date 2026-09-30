// Affiche une mire de déchirure dans le Chromium du kiosque : barres verticales blanches qui défilent
// vite sur fond noir. Une image déchirée se voit comme une barre cassée en deux, décalée à une hauteur.
const H = `<body style="margin:0;background:#000;overflow:hidden"><canvas id=c width=1920 height=1080></canvas><script>
const x=c.getContext('2d');let t=0;(function f(){x.fillStyle='#000';x.fillRect(0,0,1920,1080);x.fillStyle='#fff';
for(let i=0;i<8;i++)x.fillRect(((t*24)+i*240)%1920,0,60,1080);t++;x.font='40px sans-serif';x.fillText('MIRE DECHIRURE — FlipFB none',40,1040);requestAnimationFrame(f)})()</script>`;
const page = (await (await fetch('http://127.0.0.1:9222/json')).json()).find(t => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
ws.send(JSON.stringify({ id: 1, method: 'Page.navigate', params: { url: 'data:text/html,' + encodeURIComponent(H) } }));
await new Promise(r => setTimeout(r, 1000)); ws.close();
