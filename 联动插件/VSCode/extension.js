'use strict';
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const {createRunner}=require('./runner');
const actions=['run','chooseRun','runFile','build','test','stop','openProblems','openConsole'];

function activate(context) {
  const root = path.join(os.homedir(), 'Library', 'Application Support', 'ForeverYoungPet', 'Bridge');
  for (const name of ['events', 'commands', 'acks']) fs.mkdirSync(path.join(root, name), {recursive:true, mode:0o700});
  const instance = crypto.randomUUID();
  const active = new Map();
  let sequence = 0, current = {state:'idle',runID:'',title:'VS Code',project:vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || ''};
  const processed = new Set();
  let metadata={pluginVersion:'3.7.1'};
  const write = (folder, name, object) => {
    const target = path.join(root,folder,name+'.json'), temp = target+'.tmp';
    fs.writeFileSync(temp,JSON.stringify(object),{mode:0o600}); fs.renameSync(temp,target);
  };
  const publish = () => {
    try { write('events',instance,{version:1,source:'vscode',instance,sequence:++sequence,sentAt:Date.now(),...current,activeCount:active.size,actions,metadata}); }
    catch (error) { console.warn('Forever Young local mailbox unavailable:',error.code); }
  };
  const event = (state,runID,title,project) => {current={state,runID,title:String(title).slice(0,500),project:project || ''};publish();};
  const taskIDs = new WeakMap();
  function startTask(execution) {
    if (taskIDs.has(execution)) return;
    const id=crypto.randomUUID(); taskIDs.set(execution,id); active.set(id,execution);
    event('working',id,execution.task.name,execution.task.scope?.uri?.fsPath || current.project);
  }
  const finishedTasks = new WeakSet();
  function endTask(execution, code) {
    if (finishedTasks.has(execution)) return;
    finishedTasks.add(execution);
    const id=taskIDs.get(execution) || crypto.randomUUID();active.delete(id);
    // Undefined exit codes mean stopped/unconfirmed, never a successful test.
    event(code === 0 ? 'completed' : typeof code === 'number' ? 'failed' : 'interrupted',id,execution.task.name,execution.task.scope?.uri?.fsPath || current.project);
  }
  const processEnds = new WeakSet();
  context.subscriptions.push(vscode.tasks.onDidStartTask(e=>startTask(e.execution)),
    vscode.tasks.onDidEndTaskProcess(e=>{processEnds.add(e.execution);endTask(e.execution,e.exitCode);}),
    vscode.tasks.onDidEndTask(e=>{setTimeout(()=>{if(!processEnds.has(e.execution)) endTask(e.execution,undefined);},200);}),
    vscode.debug.onDidStartDebugSession(s=>{active.set(s.id,s);event('working',s.id,s.name,s.workspaceFolder?.uri.fsPath || current.project);}),
    vscode.debug.onDidTerminateDebugSession(s=>{active.delete(s.id);event('interrupted',s.id,s.name,s.workspaceFolder?.uri.fsPath || current.project);}));
  // Debug termination lacks an exit code in this public API; label stopped, not success.
  for (const execution of vscode.tasks.taskExecutions) startTask(execution);
  if(vscode.debug.activeDebugSession) {const s=vscode.debug.activeDebugSession;active.set(s.id,s);event('working',s.id,s.name,s.workspaceFolder?.uri.fsPath || current.project);}
  const run=createRunner(vscode,context);
  async function refresh() {try {metadata=await run.describe();publish();}catch(error){metadata={pluginVersion:'3.7.1',diagnosticError:String(error.message).slice(0,400)};publish();}}
  context.subscriptions.push(vscode.window.onDidChangeActiveTextEditor(refresh),vscode.workspace.onDidChangeConfiguration(refresh));
  async function command(action,expectedToken) {
    if(action==='openProblems')return vscode.commands.executeCommand('workbench.actions.view.problems');
    if(action==='openConsole')return vscode.commands.executeCommand('workbench.action.terminal.focus');
    if (!vscode.workspace.isTrusted) throw new Error('Workspace must be trusted before running configurations.');
    if (action === 'stop') {
      if (active.size === 0) return;
      const chosen = await vscode.window.showQuickPick([...active.entries()].map(([id,execution])=>({label:execution.task?.name || execution.name,description:'Stop this running task',id,execution})),{placeHolder:'Forever Young · Choose a task to stop'});
      if (chosen) chosen.execution.task ? chosen.execution.terminate() : await vscode.debug.stopDebugging(chosen.execution);
      return;
    }
    try {await run(action,expectedToken);await refresh();}catch(error){await vscode.window.showErrorMessage('Forever Young: '+error.message);throw error;}
  }
  for(const action of actions) context.subscriptions.push(vscode.commands.registerCommand('foreverYoung.'+action,()=>command(action).catch(()=>{})));
  let polling=false;
  async function poll() {
    if(polling) return;polling=true;
    try {
      for (const file of fs.readdirSync(path.join(root,'commands')).slice(0,100)) {
        if (!file.startsWith(instance+'-') || !file.endsWith('.json')) continue;
        const url=path.join(root,'commands',file), stat=fs.lstatSync(url);
        if (!stat.isFile() || stat.isSymbolicLink() || stat.size>4096) continue;
        let value;try{value=JSON.parse(fs.readFileSync(url,'utf8'));}catch{fs.unlinkSync(url);continue;}
        if(value.version!==1 || value.instance!==instance || value.source!=='vscode' || !actions.includes(value.action) || typeof value.id!=='string' || !/^[0-9a-f-]{36}$/i.test(value.id) || Math.abs(Date.now()-value.sentAt)>15000) {fs.unlinkSync(url);continue;}
        if(processed.has(value.id)) {fs.unlinkSync(url);continue;}
        processed.add(value.id);fs.unlinkSync(url);
        try {await command(value.action,value.expectedToken);write('acks',value.id,{version:1,id:value.id,ok:true});}
        catch(error){write('acks',value.id,{version:1,id:value.id,ok:false,error:String(error.message).slice(0,400)});}
      }
    } catch(error){console.warn('Forever Young command mailbox:',error.code || error.name);}
    finally {polling=false;}
  }
  refresh();
  const heartbeat=setInterval(refresh,10000), commands=setInterval(poll,500);
  context.subscriptions.push({dispose(){clearInterval(heartbeat);clearInterval(commands);try{fs.unlinkSync(path.join(root,'events',instance+'.json'));}catch{}}});
}
exports.activate=activate;
