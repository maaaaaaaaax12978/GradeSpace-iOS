// Cross-platform checks; an actual iOS compile runs on the macOS workflow.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {average,validate}=require('../GradeSpace/Web/core.js');
assert.equal(average([]),null);
assert.equal(average([{value:3,weight:1},{value:5,weight:2}]),13/3);
const journal={version:1,theme:'light',subjects:[{id:'s',name:'Математика',color:0,marks:[{id:'r',value:3,weight:1,ghost:false,note:'',date:'2026-10-23T10:00:00Z'},{id:'g',value:5,weight:2,ghost:true,note:'',date:'2026-10-23T10:00:00Z'}]}]};
assert.equal(average(journal.subjects[0].marks.filter(m=>!m.ghost)),3);
const migrated=validate(JSON.parse(JSON.stringify(journal)));
assert.equal(migrated.subjects[0].marks[0].quarter,1);
assert.deepEqual(migrated.subjects[0].closedQuarters,[]);
assert.deepEqual(validate(JSON.parse(JSON.stringify(migrated))),migrated);
for(const patch of [{value:6},{weight:0},{weight:1.5},{ghost:'yes'},{date:'invalid'}]){const j=JSON.parse(JSON.stringify(journal));Object.assign(j.subjects[0].marks[0],patch);assert.throws(()=>validate(j));}

function boot(seed){
 const nodes=new Map(),events={},docEvents={},messages={journal:[],exportJournal:[],importJournal:[],appearance:[]};
 function node(selector){if(!nodes.has(selector))nodes.set(selector,{innerHTML:'',content:'',value:'',open:false,onclick:null,classList:{add(){},remove(){},toggle(){}},addEventListener(){},showModal(){this.open=true;},close(){this.open=false;},querySelector(){return {onclick:null}},focus(){}});return nodes.get(selector)}
 const context={console,Blob,URL,Date,Math,JSON,Number,Array,String,Map,Set,Error,parseInt,crypto:require('node:crypto').webcrypto,
  document:{querySelector:node,querySelectorAll:()=>[],documentElement:{dataset:{}},addEventListener:(n,f)=>docEvents[n]=f},
  navigator:{},location:{protocol:'file:'},matchMedia:()=>({matches:false,addEventListener(){}}),
  setTimeout:()=>1,clearTimeout(){},localStorage:{getItem(){throw Error('Native must not read browser storage')},setItem(){throw Error('Native must not write browser storage')}},
  GradeSpaceNative:{journal:seed},webkit:{messageHandlers:Object.fromEntries(Object.keys(messages).map(k=>[k,{postMessage:v=>messages[k].push(v)}]))},
  addEventListener:(n,f)=>events[n]=f,scrollTo(){}};
 context.window=context;context.globalThis=context;vm.createContext(context);
 vm.runInContext(fs.readFileSync('GradeSpace/Web/core.js','utf8'),context);
 vm.runInContext(fs.readFileSync('GradeSpace/Web/app.js','utf8'),context);
 const click=dataset=>docEvents.click({target:{closest:()=>({dataset,parentElement:{querySelectorAll:()=>[]}})}});
 return {nodes,events,docEvents,messages,node,click};
}

async function main(){
 const a=boot(null);
 a.click({action:'add-subject'});a.node('#subject-name').value='Математика';a.docEvents.submit({preventDefault(){},target:{id:'subject-form'}});
 let saved=JSON.parse(a.messages.journal.at(-1));assert.equal(saved.subjects[0].name,'Математика');
 a.click({action:'add-mark'});a.click({action:'mark-grade',value:'3'});a.node('#mark-weight').value='1';a.node('#mark-note').value='Контрольная';a.docEvents.submit({preventDefault(){},target:{id:'mark-form'}});
 saved=JSON.parse(a.messages.journal.at(-1));assert.equal(saved.subjects[0].marks[0].value,3);assert.equal(saved.subjects[0].marks[0].ghost,false);
 a.click({action:'nav',page:'forecast'});a.node('#plan-weight').value='1';a.click({action:'weight',prefix:'plan',diff:'1'});a.click({action:'save-plan'});
 saved=JSON.parse(a.messages.journal.at(-1));assert.equal(saved.subjects[0].marks[1].weight,2);assert.equal(saved.subjects[0].marks[1].ghost,true);assert.equal(average(saved.subjects[0].marks),13/3);
 const b=boot(JSON.stringify(saved));assert.match(b.node('#app').innerHTML,/4,33/);assert.match(b.node('#app').innerHTML,/3,00/);
 b.click({action:'theme',theme:'dark'});assert.equal(JSON.parse(b.messages.journal.at(-1)).theme,'dark');
 b.click({action:'export'});assert.equal(JSON.parse(b.messages.exportJournal.at(-1).text).subjects.length,1);
 b.click({action:'import'});assert.equal(b.messages.importJournal.length,1);
 b.events['gradespace-import']({detail:{text:JSON.stringify(journal)}});
 await Promise.resolve();await Promise.resolve();b.node('#confirm-yes').onclick();
 assert.equal(JSON.parse(b.messages.journal.at(-1)).subjects[0].id,'s');
 b.events['gradespace-save-error']({detail:{message:'Disk full'}});assert.match(b.node('#app').innerHTML,/Не удалось сохранить/);
 const corrupt=boot('broken');assert.match(corrupt.node('#app').innerHTML,/не удалось прочитать/);assert.equal(corrupt.messages.journal.length,0);
 const core=require('../GradeSpace/Web/core.js');
 const q=boot(null);
 q.click({action:'add-subject'});q.node('#subject-name').value='Физика';q.docEvents.submit({preventDefault(){},target:{id:'subject-form'}});
 const latest=()=>JSON.parse(q.messages.journal.at(-1));
 const sid=latest().subjects[0].id;
 function submit(id,dataset={}){q.docEvents.submit({preventDefault(){},target:{id,dataset}})}
 function add(value,quarter,ghost=false,weight=1){q.click({action:'period',period:String(quarter)});q.click({action:'add-mark'});q.click({action:'mark-grade',value:String(value)});q.node('#mark-quarter').value=String(quarter);q.node('#mark-weight').value=String(weight);q.node('#mark-note').value='';if(ghost){const handlers=q.docEvents;handlers.click({target:{closest:()=>({dataset:{action:'mark-ghost'},setAttribute(){},querySelector:()=>({classList:{toggle(){}}})})}})}submit('mark-form');}
 function finish(value){q.click({action:'finish-quarter'});q.node('#quarter-final').value=String(value);submit('finish-form');}
 add(3,1,false,1);add(5,1,true,2);add(5,2,false,1);
 assert.equal(core.average(core.quarterMarks(latest().subjects[0],1).filter(m=>!m.ghost)),3);
 assert.equal(core.average(core.quarterMarks(latest().subjects[0],2)),5);
 finish(5);let s=latest().subjects[0];assert.equal(core.isClosed(s,2),true);assert.equal(s.quarterFinals[2],5);
 const markId=s.marks.find(m=>m.quarter===2).id;
 q.click({action:'remove-mark',id:markId,sub:sid});assert.equal(latest().subjects[0].marks.length,3);
 q.node('#mark-quarter').value='2';q.node('#mark-weight').value='1';submit('mark-form');assert.equal(latest().subjects[0].marks.length,3);
 q.click({action:'period',period:'1'});finish(3);s=latest().subjects[0];assert.equal(s.quarterFinals[1],3);assert.equal(core.annual(s).official,null);assert.equal(core.annual(s).completed,2);
 add(4,3);finish(4);add(5,4);finish(5);s=latest().subjects[0];assert.equal(core.annual(s).average,4.25);assert.equal(core.annual(s).official,4);
 q.click({action:'period',period:'year'});q.click({action:'subject',id:sid});assert.match(q.node('#app').innerHTML,/Все четыре четверти завершены/);
 q.click({action:'year-final'});q.node('#year-final').value='5';submit('year-form');assert.equal(core.annual(latest().subjects[0]).official,5);
 q.click({action:'period',period:'2'});q.click({action:'reopen-quarter'});q.node('#confirm-yes').onclick();s=latest().subjects[0];assert.equal(core.isClosed(s,2),false);assert.equal(s.yearFinal,null);assert.equal(core.annual(s).official,null);assert.equal(s.marks.length,5);
 q.click({action:'period',period:'3'});q.click({action:'reopen-quarter'});q.node('#confirm-yes').onclick();
 q.click({action:'move-mark',id:markId,sub:sid});q.node('#move-quarter').value='3';submit('move-form',{sub:sid,mark:markId});assert.equal(latest().subjects[0].marks.find(m=>m.id===markId).quarter,3);
 const restored=boot(JSON.stringify(latest()));assert.match(restored.node('#app').innerHTML,/III/);
 const roundSubject=validate({version:1,subjects:[{id:'x',name:'Test',marks:[{...journal.subjects[0].marks[0],id:'1',value:4,quarter:1},{...journal.subjects[0].marks[0],id:'2',value:5,quarter:1}]}]}).subjects[0];assert.equal(core.quarterResult(roundSubject,1),5);assert.equal(core.quarterResult(roundSubject,4),null);
 for(const bad of [0,5,1.5]){const broken=JSON.parse(JSON.stringify(migrated));broken.subjects[0].marks[0].quarter=bad;assert.throws(()=>validate(broken));}
 const brokenFinal=JSON.parse(JSON.stringify(migrated));brokenFinal.subjects[0].closedQuarters=[1];assert.throws(()=>validate(brokenFinal));
 console.log('PASS: native persistence/import/export, quarter isolation, closing without ghosts, locking, reopening, transfers, annual completion, rounding and legacy migration.');
}
main().catch(e=>{console.error(e);process.exitCode=1});
