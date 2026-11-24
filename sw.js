self.addEventListener('message',event=>{if(event.data&&event.data.type==='SKIP_WAITING')self.skipWaiting()});
const CACHE='sabka-hissa-shell-v130';
const FILES=['/sabka_hissa/','/sabka_hissa/index.html','/sabka_hissa/member.html','/sabka_hissa/member-config.js','/sabka_hissa/manifest.webmanifest','/sabka_hissa/icon.svg','/sabka_hissa/sath-signboard-handshake.webp'];
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)));self.skipWaiting()});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('sabka-hissa-shell-')&&k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim()});
self.addEventListener('fetch',event=>{
 if(event.request.method!=='GET')return;
 const url=new URL(event.request.url);
 if(url.origin!==self.location.origin)return;
 if(event.request.mode==='navigate'||url.pathname.endsWith('.html')||url.pathname==='/sabka_hissa/'){
  event.respondWith((async()=>{
   const cached=await caches.match(event.request);
   const refresh=fetch(event.request,{cache:'no-store'}).then(response=>{
    if(response&&response.ok){const copy=response.clone();caches.open(CACHE).then(c=>c.put(event.request,copy))}
    return response;
   });
   if(cached){event.waitUntil(refresh.then(()=>{}).catch(()=>{}));return cached}
   try{return await refresh}catch(e){return caches.match('/sabka_hissa/')}
  })());
  return;
 }
 event.respondWith(caches.match(event.request).then(cached=>cached||fetch(event.request).then(response=>{const copy=response.clone();caches.open(CACHE).then(c=>c.put(event.request,copy));return response})));
});