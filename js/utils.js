export const qs=(selector,root=document)=>root.querySelector(selector)
export const qsa=(selector,root=document)=>[...root.querySelectorAll(selector)]
export const escapeHtml=(value='')=>String(value).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))
export const formatDate=value=>new Intl.DateTimeFormat('en',{dateStyle:'medium'}).format(new Date(value))
export const debounce=(fn,delay=250)=>{let id;return(...args)=>{clearTimeout(id);id=setTimeout(()=>fn(...args),delay)}}
export const queryParam=name=>new URLSearchParams(location.search).get(name)
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const isValidUuid=value=>typeof value==='string'&&UUID_RE.test(value)
export const getCurrentEventId=()=>{const id=queryParam('id');return isValidUuid(id)?id:null}
export const setBusy=(button,busy,label='Working…')=>{if(!button)return;button.dataset.label??=button.textContent;button.disabled=busy;button.textContent=busy?label:button.dataset.label}
export function statusLabel(value='not_started'){return value.replaceAll('_',' ').replace(/\b\w/g,c=>c.toUpperCase())}
export function statusClass(value=''){return `status status-${value.replaceAll('_','-')}`}
