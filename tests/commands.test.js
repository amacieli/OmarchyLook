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
const C3=new Function(fs.readFileSync('qml/keys/Commands.js','utf8').replace('.pragma library','')+';return {applyBindings,normKey,normToken,presets}')();
eq(C3.normKey('Ctrl-r'),'C-r','norm ctrl'); eq(C3.normKey('ctrl-shift-v'),'C-S-v','norm cs'); eq(C3.normKey('g  m'),'g m','chord');
eq(C3.normKey('PageUp'),'PgUp','pgup'); eq(C3.normKey('f9'),'F9','f9'); eq(C3.normKey('banana'),null,'bad'); eq(C3.normKey('C-1'),'C-1','digit');
const base=[
 {id:'mail.archive',scope:'mail',keys:['a'],title:'Archive'},
 {id:'mail.reply',scope:'mail',keys:['r'],title:'Reply'},
 {id:'go.mail',scope:'global',keys:['g m'],title:'Mail'},
 {id:'item.delete',scope:'global',keys:['x'],title:'Delete'},
 {id:'g1',scope:'global',keys:['g g'],title:'Top'},
];
let r=C3.applyBindings(base,{});
eq(r.problems.length,0,'defaults clean'); eq(r.commands[0].keys[0],'a','default key'); eq(r.commands[0].custom,undefined,'not custom');
r=C3.applyBindings(base,{bindings:{'mail.archive':['e'],'item.delete':[]}});
eq(r.commands[0].keys.join(),'e','replaced'); eq(r.commands[0].custom,true,'custom'); eq(r.commands[3].keys.length,0,'unbound'); eq(r.problems.length,0,'no problems');
r=C3.applyBindings(base,{preset:'outlook'});
eq(r.commands[1].keys.join(),'r,C-r','preset adds'); eq(r.commands[3].keys.join(),'x,Delete','preset adds delete');
r=C3.applyBindings(base,{bindings:{'mail.archive':['r']}});
eq(r.problems.length,1,'same-scope duplicate'); 
r=C3.applyBindings(base,{bindings:{'nope':['q'],'mail.reply':['Hyper-z']},preset:'zzz'});
eq(r.problems.length,3,'unknown id, bad key, unknown preset');
r=C3.applyBindings(base,{bindings:{'go.mail':['g']}});
eq(r.problems.length,1,'chord prefix hides chord'); 
r=C3.applyBindings(base,{error:'settings.toml: bad'}); eq(r.problems[0],'settings.toml: bad','parse error surfaced');
console.log('ok3');
