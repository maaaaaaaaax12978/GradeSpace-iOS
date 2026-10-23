// Cross-platform checks; an actual iOS compile runs on the macOS workflow.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {average,validate}=require('../GradeSpace/Web/core.js');
assert.equal(average([]),null);
assert.equal(average([{value:3,weight:1},{value:5,weight:2}]),13/3);
const journal={version:1,theme:'light',subjects:[{id:'s',name:'Математика',color:0,marks:[{id:'r',value:3,weight:1,ghost:false,note:'',date:'2026-10-23T10:00:00Z'},{id:'g',value:5,weight:2,ghost:true,note:'',date:'2026-10-23T10:00:00Z'}]}]};
assert.equal(average(journal.subjects[0].marks.filter(m=>!m.ghost)),3);
assert.deepEqual(validate(JSON.parse(JSON.stringify(journal))),journal);
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
 console.log('PASS: weighted math, validation, native save/restore, theme, import/export bridge, error reporting and corruption protection.');
}
main().catch(e=>{console.error(e);process.exitCode=1});
