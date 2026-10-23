(function(root){
 const average=marks=>{const w=marks.reduce((s,m)=>s+m.weight,0);return w?marks.reduce((s,m)=>s+m.value*m.weight,0)/w:null};
 const quarters=[1,2,3,4];
 const quarterMarks=(s,q)=>s.marks.filter(m=>(m.quarter??1)===q);
 const isClosed=(s,q)=>(s.closedQuarters||[]).includes(q);
 function quarterResult(s,q,forecast=false){if(isClosed(s,q))return s.quarterFinals[q];const n=average(quarterMarks(s,q).filter(m=>forecast||!m.ghost));return n===null?null:Math.round(n);}
 function annual(s,forecast=false){const completed=quarters.filter(q=>isClosed(s,q)).length;const finals=quarters.map(q=>isClosed(s,q)?s.quarterFinals[q]:forecast?quarterResult(s,q,true):null).filter(x=>x!==null);const mean=average(finals.map(value=>({value,weight:1}))),calculated=mean===null?null:Math.round(mean);return {completed,used:finals.length,average:mean,calculated,official:completed===4?(s.yearFinal??calculated):null};}
 function validate(s){
  if(!s||s.version!==1||!Array.isArray(s.subjects)||s.subjects.length>500)throw Error('Неверный формат журнала');const ids=new Set();
  for(const sub of s.subjects){
   if(typeof sub.id!=='string'||ids.has(sub.id)||typeof sub.name!=='string'||!sub.name.trim()||sub.name.length>80||!Array.isArray(sub.marks)||sub.marks.length>20000)throw Error('Неверные данные предмета');ids.add(sub.id);sub.color=Number.isInteger(sub.color)&&sub.color>=0&&sub.color<6?sub.color:0;
   if(sub.quarterFinals===undefined)sub.quarterFinals={};if(!sub.quarterFinals||typeof sub.quarterFinals!=='object'||Array.isArray(sub.quarterFinals))throw Error('Неверные итоги четвертей');for(const [q,v] of Object.entries(sub.quarterFinals))if(!['1','2','3','4'].includes(q)||!Number.isInteger(v)||v<1||v>5)throw Error('Неверная четвертная оценка');
   if(sub.closedQuarters===undefined)sub.closedQuarters=[];if(!Array.isArray(sub.closedQuarters)||new Set(sub.closedQuarters).size!==sub.closedQuarters.length||sub.closedQuarters.some(q=>!quarters.includes(q)||!Number.isInteger(sub.quarterFinals[q])))throw Error('Неверные завершённые четверти');
   if(sub.yearFinal===undefined)sub.yearFinal=null;if(sub.yearFinal!==null&&(!Number.isInteger(sub.yearFinal)||sub.yearFinal<1||sub.yearFinal>5||sub.closedQuarters.length!==4))throw Error('Неверная годовая оценка');
   const mids=new Set();for(const m of sub.marks){if(m.quarter===undefined)m.quarter=1;if(typeof m.id!=='string'||mids.has(m.id)||!Number.isInteger(m.value)||m.value<1||m.value>5||!Number.isInteger(m.weight)||m.weight<1||m.weight>100||typeof m.ghost!=='boolean'||typeof m.note!=='string'||m.note.length>200||!Number.isFinite(Date.parse(m.date))||!quarters.includes(m.quarter))throw Error('Неверная оценка');mids.add(m.id);}
  }
  s.theme=['system','light','dark'].includes(s.theme)?s.theme:'system';s.period=s.period==='year'||quarters.includes(s.period)?s.period:1;s.lastQuarter=quarters.includes(s.lastQuarter)?s.lastQuarter:typeof s.period==='number'?s.period:1;return s;
 }
 const api={average,validate,quarters,quarterMarks,isClosed,quarterResult,annual};if(typeof module!=='undefined')module.exports=api;root.GradeCore=api;
})(typeof window!=='undefined'?window:globalThis);
