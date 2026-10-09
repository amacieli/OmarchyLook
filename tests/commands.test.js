const fs=require('fs');
const src=fs.readFileSync('qml/keys/Commands.js','utf8').replace('.pragma library','');
const C=new Function(src+';return {resolve,applicable,fuzzy,keyLabel}')();
const run=()=>{};
const cmds=[
 {id:'down',scope:'global',keys:['j','Down'],run},
 {id:'rdown',scope:'reader',keys:['j'],run},
 {id:'top',scope:'global',keys:['g g'],run},
 {id:'gm',scope:'global',keys:['g m'],run},
 {id:'cal',scope:'calendar/list',keys:['j'],run},
 {id:'off',scope:'global',keys:['z'],run,when:()=>false},
];
const eq=(a,b,m)=>{ if(a!==b){console.error('FAIL',m,a,b);process.exit(1)} };
eq(C.resolve(cmds,['list','global'],['j']).exact.id,'down','global j');
eq(C.resolve(cmds,['reader','global'],['j']).exact.id,'rdown','inner wins');
eq(C.resolve(cmds,['list','calendar/list','global'],['j']).exact.id,'cal','view scope');
eq(C.resolve(cmds,['list','global'],['g']).prefixes.length,2,'prefix');
eq(C.resolve(cmds,['list','global'],['g']).exact,null,'no exact');
eq(C.resolve(cmds,['list','global'],['g','m']).exact.id,'gm','chord');
eq(C.resolve(cmds,['list','global'],['g','x']).exact,null,'dead chord');
eq(C.resolve(cmds,['global'],['z']).exact,null,'when');
eq(C.applicable(cmds,['reader','global']).filter(c=>c.id==='down'||c.id==='rdown').length,2,'applicable');
eq(C.fuzzy('gtc','Go to calendar'),true,'fuzzy');eq(C.fuzzy('zq','Go'),false,'fuzzy2');
console.log('ok');
