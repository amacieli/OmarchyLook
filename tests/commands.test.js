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
const C2=new Function(fs.readFileSync('qml/keys/Commands.js','utf8').replace('.pragma library','')+';return {parseEx,findEx,grouped,sectionName}')();
let p=C2.parseEx(':goto cal'); eq(p.name,'goto','ex name'); eq(p.arg,'cal','ex arg'); eq(p.hasSpace,true,'space');
eq(C2.parseEx('q').hasSpace,false,'nospace'); eq(C2.parseEx('   '),null,'empty');
eq(C2.findEx([{id:'a',ex:['q','quit'],keys:[]}],'quit').id,'a','findEx'); eq(C2.findEx([{id:'a',ex:['q'],keys:[]}],'z'),null,'findEx none');
const g=C2.grouped([{scope:'global',keys:['j']},{scope:'mail',keys:['r']},{scope:'mail',keys:[],id:'x'},{scope:'tasks/list',keys:['f']}],['mail']);
eq(g[0].scope,'mail','active first'); eq(g[0].commands.length,1,'keyless omitted'); eq(g.length,3,'groups');
console.log('ok2');
