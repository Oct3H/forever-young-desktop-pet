'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto'),{spawn}=require('child_process');
const {compilerError,stamp}=require('./errors');

exports.createRunner=(vscode,context,report=()=>{})=>{
  const owned=new Map(),projectTasks=new Set(),projectDebug=new Set();let pendingDebug;let lastError={};
  context.subscriptions.push(vscode.tasks.onDidEndTask(e=>projectTasks.delete(e.execution)));
  if(vscode.debug?.onDidStartDebugSession)context.subscriptions.push(vscode.debug.onDidStartDebugSession(s=>{if(pendingDebug && s.name===pendingDebug.name && s.workspaceFolder?.uri.toString()===pendingDebug.folder)projectDebug.add(s);}));
  if(vscode.debug?.onDidTerminateDebugSession)context.subscriptions.push(vscode.debug.onDidTerminateDebugSession(s=>projectDebug.delete(s)));
  const fail=(op,error)=>{lastError=stamp(error);report({state:'failed',runID:op.id,title:op.name,metadata:{phase:'failed',ownedCount:String(owned.size),...lastError}});};
  const temporary=new Set();
  const cleanup=folder=>{if(temporary.delete(folder)) fs.rmSync(folder,{recursive:true,force:true});};
  context.subscriptions.push({dispose(){for(const folder of [...temporary])cleanup(folder);}});
  function executable(value) {
    if(typeof value!=='string' || !value) return;
    const candidates=path.isAbsolute(value)?[value]:(process.env.PATH || '').split(path.delimiter).filter(Boolean).map(folder=>path.join(folder,value));
    for(const candidate of candidates) try {if(fs.statSync(candidate).isFile()){fs.accessSync(candidate,fs.constants.X_OK);return candidate;}}catch{}
  }
  function key(choice) {
    const identity=choice.task?[choice.task.scope?.uri?.toString(),choice.task.source,choice.task.name,choice.task.definition]:[choice.folder.uri.toString(),choice.config];
    return crypto.createHash('sha256').update(JSON.stringify(identity)).digest('hex');
  }
  // Process tasks participate in VS Code's real lifecycle events. Arguments never go through a shell.
  async function processTask(folder,file,command,args,name,done,operationID,onStarted) {
    const requestID=crypto.randomUUID();let finished=false;
    let processStart,processEnd,taskEnd;
    const finish=code=>{if(finished)return;finished=true;processStart.dispose();processEnd.dispose();taskEnd.dispose();done?.(code);};
    const matches=event=>event.execution.task.definition.requestID===requestID;
    processStart=vscode.tasks.onDidStartTaskProcess(event=>{if(matches(event))onStarted?.(event.execution);});
    processEnd=vscode.tasks.onDidEndTaskProcess(event=>{if(matches(event))finish(event.exitCode);});
    taskEnd=vscode.tasks.onDidEndTask(event=>{if(matches(event))setTimeout(()=>finish(undefined),200);});
    context.subscriptions.push(processStart,processEnd,taskEnd);
    const task=new vscode.Task({type:'foreverYoungFile',file,requestID,operationID,phase:'running'},folder || vscode.TaskScope.Workspace,name,'Forever Young',new vscode.ProcessExecution(command,args,{cwd:path.dirname(file)}));
    task.presentationOptions={reveal:vscode.TaskRevealKind.Always,focus:true};
    try {return await vscode.tasks.executeTask(task);}catch(error){finish(undefined);throw error;}
  }
  async function runFile(expectedToken) {
    const document=vscode.window.activeTextEditor?.document;
    if(!document || document.uri.scheme!=='file') throw new Error('Open a local source file in VS Code first.');
    const file=document.uri.fsPath,extension=path.extname(file).toLowerCase();
    if(expectedToken && crypto.createHash('sha256').update(file).digest('hex')!==expectedToken)throw new Error('Current file changed. Refresh the pet preview before running.');
    if(!['.py','.js','.mjs','.cjs','.c','.cc','.cpp','.cxx'].includes(extension)) throw new Error('Use a project configuration for this file type.');
    if(owned.size || projectTasks.size || projectDebug.size) throw new Error('A current-file run is already active in this window. Stop it or wait for it to finish.');
    const op={id:crypto.randomUUID(),file,name:path.basename(file),stopped:false};owned.set(file,op);lastError={};
    const status=phase=>report({state:'working',runID:op.id,title:op.name,metadata:{phase,ownedCount:String(owned.size),errorSummary:'',errorToken:'',errorFile:'',errorLine:'',errorColumn:''}});
    const finish=code=>{
      if(owned.get(file)!==op)return;owned.delete(file);
      if(op.folder)cleanup(op.folder);
      if(op.stopped || code===undefined || code===130 || code===143)report({state:'interrupted',runID:op.id,title:op.name,metadata:{phase:'interrupted',ownedCount:String(owned.size)}});
      else if(code===0)report({state:'completed',runID:op.id,title:op.name,metadata:{phase:'completed',ownedCount:String(owned.size)}});
      else fail(op,{errorKind:'runtime',errorSummary:'Program exited with code '+code+'. See the run terminal.'});
    };
    const execute=async(command,args)=>{
      if(op.stopped){finish(undefined);return;}
      // Report running only once the real process exists. Stop during startup is latched.
      op.kill=undefined;op.execution=undefined;
      await processTask(folder,file,command,args,`Forever Young · Run ${op.name}`,finish,op.id,execution=>{
        op.execution=execution;status('running');if(op.stopped)execution.terminate();
      });
    };
    const folder=vscode.workspace.getWorkspaceFolder(document.uri);
    try {
      status('preparing');
      if(document.isDirty && !await document.save())throw new Error('Save the current file before running.');
      if(extension==='.py') {
        let selected;try{selected=await vscode.commands.executeCommand('python.interpreterPath',document.uri);}catch{}
        const python=executable(selected) || (folder && executable(path.join(folder.uri.fsPath,'.venv','bin','python')));
        if(!python)throw new Error('Select the existing project Python interpreter in VS Code.');
        await execute(python,[file]);return;
      }
      if(['.js','.mjs','.cjs'].includes(extension)) {
        const node=executable('node') || executable('/opt/homebrew/bin/node') || executable('/usr/local/bin/node');
        if(!node)throw new Error('No existing Node.js executable was found.');
        await execute(node,[file]);return;
      }
      const cpp=extension!=='.c',configured=vscode.workspace.getConfiguration('C_Cpp',document.uri).get('default.compilerPath');
      let compiler=configured?executable(configured.replace('${workspaceFolder}',folder?.uri.fsPath || path.dirname(file))):executable(cpp?'clang++':'clang') || executable(cpp?'/usr/bin/clang++':'/usr/bin/clang');
      if(cpp && compiler){const driver={clang:'clang++',gcc:'g++',cc:'c++'}[path.basename(compiler)];if(driver)compiler=executable(path.join(path.dirname(compiler),driver)) || compiler;}
      if(!compiler)throw new Error('No existing C/C++ compiler was found.');
      op.folder=fs.mkdtempSync(path.join(os.tmpdir(),'forever-young-run-'));temporary.add(op.folder);
      const output=path.join(op.folder,'program');status('compiling');
      const write=new vscode.EventEmitter(),close=new vscode.EventEmitter();let child,closed=false,stderr='';
      const complete=code=>{
        if(closed)return;closed=true;close.fire(typeof code==='number'?Math.max(0,code):1);
        if(op.stopped){finish(undefined);return;}
        if(code!==0){owned.delete(file);cleanup(op.folder);fail(op,compilerError(stderr,file));return;}
        execute(output,[]).catch(error=>{owned.delete(file);cleanup(op.folder);fail(op,{errorKind:'runtime',errorSummary:error.message});});
      };
      const pty={onDidWrite:write.event,onDidClose:close.event,open(){
        if(op.stopped){complete(undefined);return;}
        child=spawn(compiler,[cpp?'-std=c++17':'-std=c17','-fdiagnostics-color=never',file,'-o',output],{cwd:path.dirname(file)});
        op.kill=()=>{op.stopped=true;child.kill('SIGTERM');};
        child.stdout.on('data',data=>write.fire(data.toString().replace(/\r?\n/g,'\r\n')));
        child.stderr.on('data',data=>{stderr=(stderr+data.toString()).slice(-16384);write.fire(data.toString().replace(/\r?\n/g,'\r\n'));});
        child.on('error',error=>{stderr+=error.message;complete(1);});child.on('close',code=>complete(code));
      },close(){if(!closed){op.stopped=true;child?.kill('SIGTERM');complete(undefined);}}};
      const task=new vscode.Task({type:'foreverYoungFile',file,requestID:crypto.randomUUID(),operationID:op.id,phase:'compiling'},folder || vscode.TaskScope.Workspace,`Forever Young · Build ${op.name}`,'Forever Young',new vscode.CustomExecution(async()=>pty),['$gcc']);
      task.presentationOptions={reveal:vscode.TaskRevealKind.Always,focus:true};op.execution=await vscode.tasks.executeTask(task);
      if(op.stopped)op.execution.terminate();
    }catch(error){owned.delete(file);if(op.folder)cleanup(op.folder);fail(op,{errorKind:'launch',errorSummary:error.message});throw error;}
  }
  async function choicesFor(mode) {
    const wanted=mode==='build'?vscode.TaskGroup.Build.id:mode==='test'?vscode.TaskGroup.Test.id:null;
    const choices=(await vscode.tasks.fetchTasks()).filter(task=>task.definition.type!=='foreverYoungFile' && (!wanted || task.group?.id===wanted)).map(task=>({label:task.name,description:task.scope?.name || 'Task',task}));
    if(mode==='run') for(const folder of vscode.workspace.workspaceFolders || []) {
      for(const config of vscode.workspace.getConfiguration('launch',folder.uri).get('configurations',[])) choices.push({label:config.name,description:folder.name+' · Debug',folder,config});
    }
    const saved=context.workspaceState.get('foreverYoung.target.'+mode),defaults=choices.filter(choice=>choice.task?.group?.isDefault);
    const selected=choices.find(choice=>key(choice)===saved) || (!saved ? (defaults.length===1?defaults[0]:choices.length===1?choices[0]:undefined):undefined);
    return {choices,selected};
  }
  async function describe() {
    const file=vscode.window.activeTextEditor?.document?.uri;
    const metadata={pluginVersion:'3.8.0',bridgeAPI:'2',ideVersion:vscode.version || '',trusted:String(vscode.workspace.isTrusted),file:file?.scheme==='file'?file.fsPath:'',runtime:''};
    metadata.ownedCount=String(owned.size);Object.assign(metadata,lastError);
    metadata.fileToken=crypto.createHash('sha256').update(metadata.file).digest('hex');
    if(metadata.file.endsWith('.py')) {try {metadata.runtime=await vscode.commands.executeCommand('python.interpreterPath',file) || '';}catch{};metadata.runtime=metadata.runtime || (vscode.workspace.getWorkspaceFolder(file) && executable(path.join(vscode.workspace.getWorkspaceFolder(file).uri.fsPath,'.venv','bin','python'))) || '';}
    else if(/\.(js|mjs|cjs)$/.test(metadata.file)) metadata.runtime=executable('node') || executable('/opt/homebrew/bin/node') || executable('/usr/local/bin/node') || '';
    else if(/\.(c|cc|cpp|cxx)$/.test(metadata.file)) metadata.runtime=vscode.workspace.getConfiguration('C_Cpp',file).get('default.compilerPath') || executable(metadata.file.endsWith('.c')?'clang':'clang++') || '';
    for(const mode of ['run','build','test']) {
      const {choices,selected}=await choicesFor(mode);
      metadata[mode+'Target']=selected?selected.label:(!choices.length && mode==='run'?metadata.file:'');
      metadata[mode+'Runtime']=selected?(selected.task?.execution?.process || selected.config?.runtimeExecutable || ''):'';
      metadata[mode+'Token']=selected?key(selected):(!choices.length && mode==='run'?'file:'+metadata.fileToken:'select');
    }
    return metadata;
  }
  async function run(action,expectedToken) {
    if(!vscode.workspace.isTrusted) throw new Error('Trust this workspace before running a task.');
    if(expectedToken && action!=='openError' && action!=='runFile') {
      const snapshot=await describe(),token=action==='runFile'?snapshot.fileToken:snapshot[(action==='chooseRun'?'run':action)+'Token'];
      if(token!==expectedToken) throw new Error('Run target changed. Refresh the pet preview before running.');
    }
    if(action==='runFile') return runFile(expectedToken);
    if(['run','build','test'].includes(action) && (owned.size || projectTasks.size || projectDebug.size))throw new Error('A pet-started run is already active in this window. Stop it or wait.');
    if(action==='openError'){if(!lastError.errorToken || expectedToken!==lastError.errorToken)throw new Error('The error changed; refresh before opening it.');const file=lastError.errorFile;if(!file)return vscode.commands.executeCommand('workbench.action.terminal.focus');const folder=vscode.workspace.getWorkspaceFolder(vscode.Uri.file(file));if(!folder && file!==vscode.window.activeTextEditor?.document?.uri.fsPath)throw new Error('Error location is outside the current workspace.');const editor=await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(vscode.Uri.file(file)));const position=new vscode.Position(Math.max(0,Number(lastError.errorLine)-1),Math.max(0,Number(lastError.errorColumn || 1)-1));editor.selection=new vscode.Selection(position,position);editor.revealRange(new vscode.Range(position,position));return;}
    const mode=action==='chooseRun'?'run':action;
    const {choices,selected}=await choicesFor(mode);
    if(!choices.length) {
      if(action==='run')return runFile(expectedToken?.startsWith('file:')?expectedToken.slice(5):undefined);
      throw new Error('No matching project configuration. Use Run current file, or create a project build/test task.');
    }
    let choice=action==='chooseRun'?undefined:selected;
    if(!choice)choice=await vscode.window.showQuickPick(choices,{placeHolder:'Forever Young · Select a target once for this workspace'});
    if(!choice)return;
    await context.workspaceState.update('foreverYoung.target.'+mode,key(choice));
    if(action==='chooseRun')return;
    lastError={};
    if(choice.task)projectTasks.add(await vscode.tasks.executeTask(choice.task));
    else {pendingDebug={name:choice.config.name,folder:choice.folder.uri.toString()};try{if(!await vscode.debug.startDebugging(choice.folder,choice.config))throw new Error('The debug configuration did not start.');}finally{pendingDebug=undefined;}}
  }
  run.describe=describe;
  run.stopOwned=()=>{if(!owned.size && !projectTasks.size && !projectDebug.size)return false;for(const task of projectTasks)task.terminate();for(const session of projectDebug)vscode.debug.stopDebugging(session);for(const op of owned.values()){op.stopped=true;op.kill?.();op.execution?.terminate();}return true;};
  run.isOwned=execution=>execution.task.definition.type==='foreverYoungFile';
  return run;
};
