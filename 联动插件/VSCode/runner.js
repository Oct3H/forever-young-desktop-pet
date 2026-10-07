'use strict';
const fs=require('fs'),path=require('path'),os=require('os'),crypto=require('crypto');

exports.createRunner=(vscode,context)=>{
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
  async function processTask(folder,file,command,args,name,done) {
    const requestID=crypto.randomUUID();let finished=false;
    let processEnd,taskEnd;
    const finish=code=>{if(finished)return;finished=true;processEnd.dispose();taskEnd.dispose();done?.(code);};
    const matches=event=>event.execution.task.definition.requestID===requestID;
    processEnd=vscode.tasks.onDidEndTaskProcess(event=>{if(matches(event))finish(event.exitCode);});
    taskEnd=vscode.tasks.onDidEndTask(event=>{if(matches(event))setTimeout(()=>finish(undefined),200);});
    context.subscriptions.push(processEnd,taskEnd);
    const task=new vscode.Task({type:'foreverYoungFile',file,requestID},folder || vscode.TaskScope.Workspace,name,'Forever Young',new vscode.ProcessExecution(command,args,{cwd:path.dirname(file)}));
    task.presentationOptions={reveal:vscode.TaskRevealKind.Always,focus:true};
    try {await vscode.tasks.executeTask(task);}catch(error){finish(undefined);throw error;}
  }
  async function runFile() {
    const editor=vscode.window.activeTextEditor,document=editor?.document;
    if(!document || document.uri.scheme!=='file') throw new Error('Open a local source file in VS Code first.');
    const file=document.uri.fsPath,extension=path.extname(file).toLowerCase();
    if(!['.py','.js','.mjs','.cjs','.c','.cc','.cpp','.cxx'].includes(extension)) throw new Error('Automatic single-file run supports Python, JavaScript, C and C++. Use a project configuration for other files.');
    if(document.isDirty && !await document.save()) throw new Error('The current file could not be saved. Save it in VS Code before running.');
    const folder=vscode.workspace.getWorkspaceFolder(document.uri),name=path.basename(file);
    if(extension==='.py') {
      let selected;
      try {selected=await vscode.commands.executeCommand('python.interpreterPath',document.uri);}catch{}
      const python=executable(selected) || (folder && executable(path.join(folder.uri.fsPath,'.venv','bin','python')));
      if(!python) throw new Error('Select the project Python interpreter in VS Code, or use its existing .venv. The pet does not create environments.');
      return processTask(folder,file,python,[file],`Forever Young · Run ${name}`);
    }
    if(['.js','.mjs','.cjs'].includes(extension)) {
      const node=executable('node') || executable('/opt/homebrew/bin/node') || executable('/usr/local/bin/node');
      if(!node) throw new Error('No existing Node.js executable was found. Use a project run configuration.');
      return processTask(folder,file,node,[file],`Forever Young · Run ${name}`);
    }
    const cpp=extension!=='.c';
    const configured=vscode.workspace.getConfiguration('C_Cpp',document.uri).get('default.compilerPath');
    let compiler=configured?executable(configured.replace('${workspaceFolder}',folder?.uri.fsPath || path.dirname(file))):executable(cpp?'clang++':'clang') || executable(cpp?'/usr/bin/clang++':'/usr/bin/clang');
    if(cpp && compiler) {
      const cppDriver={clang:'clang++',gcc:'g++',cc:'c++'}[path.basename(compiler)];
      if(cppDriver) compiler=executable(path.join(path.dirname(compiler),cppDriver)) || compiler;
    }
    if(!compiler) throw new Error('No existing C/C++ compiler was found. Select the compiler in VS Code; the pet does not install tools.');
    const outputFolder=fs.mkdtempSync(path.join(os.tmpdir(),'forever-young-run-'));temporary.add(outputFolder);
    const output=path.join(outputFolder,'program');
    await processTask(folder,file,compiler,[cpp?'-std=c++17':'-std=c17',file,'-o',output],`Forever Young · Build ${name}`,code=>{
      if(code!==0){cleanup(outputFolder);return;}
      processTask(folder,file,output,[],`Forever Young · Run ${name}`,()=>cleanup(outputFolder)).catch(error=>{cleanup(outputFolder);vscode.window.showErrorMessage('Forever Young: '+error.message);});
    });
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
    const metadata={pluginVersion:'3.7.1',ideVersion:vscode.version || '',trusted:String(vscode.workspace.isTrusted),file:file?.scheme==='file'?file.fsPath:'',runtime:''};
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
    if(expectedToken) {
      const snapshot=await describe(),token=action==='runFile'?snapshot.fileToken:snapshot[(action==='chooseRun'?'run':action)+'Token'];
      if(token!==expectedToken) throw new Error('Run target changed. Refresh the pet preview before running.');
    }
    if(action==='runFile') return runFile();
    const mode=action==='chooseRun'?'run':action;
    const {choices,selected}=await choicesFor(mode);
    if(!choices.length) {
      if(action==='run')return runFile();
      throw new Error('No matching project configuration. Use Run current file, or create a project build/test task.');
    }
    let choice=action==='chooseRun'?undefined:selected;
    if(!choice)choice=await vscode.window.showQuickPick(choices,{placeHolder:'Forever Young · Select a target once for this workspace'});
    if(!choice)return;
    await context.workspaceState.update('foreverYoung.target.'+mode,key(choice));
    if(action==='chooseRun')return;
    if(choice.task)await vscode.tasks.executeTask(choice.task);
    else await vscode.debug.startDebugging(choice.folder,choice.config);
  }
  run.describe=describe;
  return run;
};
