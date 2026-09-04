/** OPD Campaign CRM - Google Sheets live sync worker
 * Required Script Properties:
 * SUPABASE_URL = https://YOUR_PROJECT.supabase.co
 * SUPABASE_SECRET_KEY = your NEW rotated Supabase secret key
 * WEBHOOK_TOKEN = any long random string (optional, for manual sync requests)
 *
 * Deploy as a Web App: Execute as Me; Who has access: Anyone.
 * Run setupTrigger() once. It checks active connections every minute.
 */
function props_(){ return PropertiesService.getScriptProperties(); }
function cfg_(){
  const p=props_();
  const c={supabaseUrl:p.getProperty('SUPABASE_URL'),secret:p.getProperty('SUPABASE_SECRET_KEY'),token:p.getProperty('WEBHOOK_TOKEN')};
  if(!c.supabaseUrl||!c.secret) throw new Error('Set SUPABASE_URL and SUPABASE_SECRET_KEY in Script Properties');
  return c;
}
function setupTrigger(){
  ScriptApp.getProjectTriggers().forEach(t=>{if(t.getHandlerFunction()==='syncAll')ScriptApp.deleteTrigger(t);});
  ScriptApp.newTrigger('syncAll').timeBased().everyMinutes(1).create();
}
function doGet(){return json_({ok:true,service:'OPD CRM Google Sheets Sync'});}
function doPost(e){
  try{
    const body=JSON.parse((e&&e.postData&&e.postData.contents)||'{}');
    const c=cfg_();
    if(c.token && body.token && body.token!==c.token)return json_({ok:false,error:'Unauthorized'});
    if(body.action==='sync')return json_({ok:true,result:syncConnection(body.connection_id),message:'Sync complete'});
    if(body.action==='sync_all')return json_({ok:true,result:syncAll(),message:'Sync complete'});
    return json_({ok:false,error:'Unknown action'});
  }catch(err){return json_({ok:false,error:String(err&&err.message||err)});}
}
function json_(obj){return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);}
function sbFetch_(path,opt){
  const c=cfg_(); opt=opt||{};
  const headers=Object.assign({'apikey':c.secret,'Content-Type':'application/json'},opt.headers||{});
  const res=UrlFetchApp.fetch(c.supabaseUrl+'/rest/v1/'+path,{method:opt.method||'get',headers:headers,payload:opt.payload||undefined,muteHttpExceptions:true});
  const code=res.getResponseCode(),text=res.getContentText();if(code<200||code>=300)throw new Error('Supabase '+code+': '+text.slice(0,500));
  return text?JSON.parse(text):null;
}
function getConnections_(){return sbFetch_('sheet_connections?select=*&active=eq.true&order=created_at.asc');}
function updateConnection_(id,patch){sbFetch_('sheet_connections?id=eq.'+encodeURIComponent(id),{method:'patch',payload:JSON.stringify(patch),headers:{Prefer:'return=minimal'}});}
function syncAll(){
  const totals={connections:0,inserted:0,duplicates:0,skipped:0,errors:0};
  getConnections_().forEach(conn=>{totals.connections++;try{const r=syncConnection(conn.id);totals.inserted+=r.inserted;totals.duplicates+=r.duplicates;totals.skipped+=r.skipped;}catch(err){totals.errors++;try{updateConnection_(conn.id,{last_sync_at:new Date().toISOString(),last_sync_status:'error',last_sync_message:String(err.message||err)});}catch(_) {}}});
  return totals;
}
function syncConnection(connectionId){
  const list=sbFetch_('sheet_connections?id=eq.'+encodeURIComponent(connectionId)+'&select=*');if(!list||!list.length)throw new Error('Connection not found');
  const conn=list[0];if(!conn.active)return {inserted:0,duplicates:0,skipped:0};
  const ss=SpreadsheetApp.openByUrl(conn.sheet_url),sh=ss.getSheetByName(conn.tab_name);if(!sh)throw new Error('Sheet tab not found: '+conn.tab_name);
  const values=sh.getDataRange().getValues();if(values.length<2){updateConnection_(conn.id,{last_sync_at:new Date().toISOString(),last_sync_status:'ok',last_sync_message:'No data rows'});return {inserted:0,duplicates:0,skipped:0};}
  const headers=values[0].map(h=>String(h||'').trim()),lower=headers.map(h=>h.toLowerCase());
  const ni=findHeader_(lower,conn.name_column,['patient_name','name','patient name','full name','fullname','customer name']);
  const pi=findHeader_(lower,conn.phone_column,['phone','mobile','phone number','mobile number','contact','contact number','phone_number','mobile_number']);
  if(ni<0||pi<0)throw new Error('Name/phone column not found. Set explicit column names in CRM.');
  const start=Math.max(1,Number(conn.last_processed_row||1)),result={inserted:0,duplicates:0,skipped:0};
  for(let r=start;r<values.length;r++){
    const rowNo=r+1,name=String(values[r][ni]||'').trim(),phone=normalize_(values[r][pi]);
    if(!name||!phone){result.skipped++;continue;}
    const key=conn.id+':'+rowNo;
    try{
      const out=sbFetch_('rpc/insert_lead_auto_assign',{method:'post',payload:JSON.stringify({p_patient_name:name,p_phone:phone,p_source_id:conn.source_id,p_campaign_id:conn.campaign_id,p_source_row_key:key,p_remarks:null})});
      if(out.inserted)result.inserted++;else if(out.duplicate)result.duplicates++;else result.skipped++;
    }catch(err){updateConnection_(conn.id,{last_sync_at:new Date().toISOString(),last_sync_status:'error',last_sync_message:'Row '+rowNo+': '+String(err.message||err),last_processed_row:rowNo-1});throw err;}
  }
  updateConnection_(conn.id,{last_processed_row:values.length,last_sync_at:new Date().toISOString(),last_sync_status:'ok',last_sync_message:`${result.inserted} inserted, ${result.duplicates} duplicates, ${result.skipped} skipped`});
  return result;
}
function findHeader_(headers,explicit,aliases){if(explicit){const x=String(explicit).trim().toLowerCase(),i=headers.indexOf(x);if(i>=0)return i;}for(const a of aliases){const i=headers.indexOf(a);if(i>=0)return i;}return -1;}
function normalize_(v){const d=String(v||'').replace(/[^0-9]/g,'');return d.length>10?d.slice(-10):d;}
