package org.foreveryoungpet.bridge;
import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.intellij.execution.ProgramRunnerUtil;
import com.intellij.execution.RunManager;
import com.intellij.execution.RunnerAndConfigurationSettings;
import com.intellij.execution.executors.DefaultRunExecutor;
import com.intellij.execution.process.ProcessHandler;
import com.intellij.execution.runners.ExecutionEnvironment;
import com.intellij.openapi.Disposable;
import com.intellij.openapi.wm.ToolWindowManager;
import com.intellij.openapi.application.ApplicationInfo;
import com.intellij.openapi.fileEditor.FileEditorManager;
import com.intellij.openapi.vfs.VirtualFile;
import com.intellij.openapi.util.JDOMUtil;
import org.jdom.Element;
import java.security.MessageDigest;
import com.jetbrains.python.run.AbstractPythonRunConfiguration;
import com.jetbrains.python.run.PythonRunConfiguration;
import com.jetbrains.python.run.PythonConfigurationType;
import com.jetbrains.python.sdk.PythonSdkUtil;
import com.intellij.openapi.module.ModuleUtilCore;
import com.intellij.openapi.roots.ProjectRootManager;
import com.intellij.openapi.fileEditor.FileDocumentManager;
import com.intellij.openapi.fileEditor.OpenFileDescriptor;
import com.intellij.openapi.vfs.LocalFileSystem;
import com.intellij.execution.process.ProcessAdapter;
import com.intellij.execution.process.ProcessEvent;
import com.intellij.openapi.util.Key;
import com.intellij.openapi.wm.WindowManager;
import java.awt.KeyboardFocusManager;
import java.awt.Window;
import java.util.regex.Pattern;
import com.intellij.openapi.application.ApplicationManager;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.ui.Messages;
import com.intellij.openapi.util.Disposer;
import com.intellij.ide.util.PropertiesComponent;
import com.intellij.openapi.ui.popup.JBPopupFactory;
import javax.swing.DefaultListCellRenderer;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.*;
import java.util.concurrent.*;

public final class PetBridge implements Disposable {
  private static final Map<Project,PetBridge> INSTANCES=new WeakHashMap<>();
  public static synchronized PetBridge get(Project project) {return INSTANCES.computeIfAbsent(project,PetBridge::new);}
  private final Project project;
  private final String instance=UUID.randomUUID().toString();
  private final Path root=Paths.get(System.getProperty("user.home"),"Library","Application Support","ForeverYoungPet","Bridge");
  private final Gson gson=new Gson();
  private final ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"ForeverYoung local bridge");t.setDaemon(true);return t;});
  private final Map<Long,ProcessHandler> active=new HashMap<>();
  private final Set<String> seen=new HashSet<>();
  private String state="idle",runID="",title;
  private int sequence=0;
  private Map<String,String> metadata=Map.of("pluginVersion","3.8.0");
  private volatile boolean disposed=false;
  private long focusedAt=0;
  private boolean wasFocused=false,launchPending=false;
  private String phase="idle";
  private final Set<Long> ownedRuns=new HashSet<>();
  private final Set<Object> ownedConfigs=Collections.newSetFromMap(new IdentityHashMap<>());
  private final Map<Long,StringBuilder> errors=new HashMap<>();
  private Map<String,String> lastError=Map.of();
  private PetBridge(Project project) {
    this.project=project;title=project.getName();Disposer.register(project,this);
    try {for(String folder:List.of("events","commands","acks")){Path p=root.resolve(folder);Files.createDirectories(p);Files.setPosixFilePermissions(p,PosixFilePermissions.fromString("rwx------"));}}
    catch(Exception ignored){return;}
    refresh();timer.scheduleAtFixedRate(this::refresh,2,2,TimeUnit.SECONDS);timer.scheduleWithFixedDelay(this::poll,500,500,TimeUnit.MILLISECONDS);
  }
  synchronized void started(ExecutionEnvironment environment,ProcessHandler handler) {
    long id=environment.getExecutionId();
    if(ownedConfigs.contains(environment.getRunProfile())) {ownedRuns.add(id);launchPending=false;}
    errors.put(id,new StringBuilder());lastError=Map.of();phase="running";
    if(handler!=null)handler.addProcessListener(new ProcessAdapter(){
      @Override public void onTextAvailable(ProcessEvent event,Key outputType){synchronized(PetBridge.this){var buffer=errors.get(id);if(buffer!=null){buffer.append(event.getText());if(buffer.length()>16384)buffer.delete(0,buffer.length()-16384);}}}
    });
    active.put(id,handler);state="working";runID=Long.toString(environment.getExecutionId());title=environment.getRunProfile().getName();publish();
  }
  synchronized void ended(ExecutionEnvironment environment,ProcessHandler handler,int code) {
    active.remove(environment.getExecutionId());ownedRuns.remove(environment.getExecutionId());ownedConfigs.remove(environment.getRunProfile());launchPending=false;
    StringBuilder output=errors.remove(environment.getExecutionId());
    if(code!=0 && code!=130 && code!=143)lastError=parseError(output==null?"":output.toString(),code);
    state=code==0?"completed":code==130||code==143?"interrupted":"failed";
    runID=Long.toString(environment.getExecutionId());phase=state;title=environment.getRunProfile().getName();publish();refresh();
  }
  private void write(String folder,String name,Object data)throws Exception {
    Path target=root.resolve(folder).resolve(name+".json"),temp=root.resolve(folder).resolve(name+".tmp");
    Files.writeString(temp,gson.toJson(data));Files.setPosixFilePermissions(temp,PosixFilePermissions.fromString("rw-------"));Files.move(temp,target,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
  }
  private synchronized void publish() {
    if(disposed)return;
    try {Map<String,Object> event=new LinkedHashMap<>();event.put("version",1);event.put("source","pycharm");event.put("instance",instance);event.put("sequence",++sequence);event.put("sentAt",System.currentTimeMillis());event.put("state",state);event.put("runID",runID);event.put("title",title.length()>500?title.substring(0,500):title);event.put("project",Objects.toString(project.getBasePath(),""));event.put("activeCount",active.size());event.put("actions",List.of("run","chooseRun","runFile","test","stop","openProblems","openConsole","openError"));Map<String,String> info=new LinkedHashMap<>(metadata);info.put("phase",phase);info.put("ownedCount",Integer.toString(ownedRuns.size()+(launchPending?1:0)));info.putAll(lastError);event.put("metadata",info);write("events",instance,event);}
    catch(Exception ignored){} // No project output or credentials are logged.
  }
  private static String hash(String value) {try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(java.nio.charset.StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
  private Map<String,String> parseError(String output,int code) {
    Map<String,String> result=new LinkedHashMap<>();result.put("errorKind","runtime");
    String summary="Program exited with code "+code+". See the Run console.";
    var lines=output.split("\\R");for(String line:lines)if(line.matches("^[A-Za-z_][A-Za-z0-9_.]*(Error|Exception):.*"))summary=line.strip();
    var match=Pattern.compile("File \"([^\"]+)\", line (\\d+)").matcher(output);
    while(match.find()){try{Path file=Paths.get(match.group(1)).toAbsolutePath().normalize();Path projectPath=Paths.get(Objects.toString(project.getBasePath(),"/not-a-project")).toAbsolutePath().normalize();if(file.startsWith(projectPath)){result.put("errorFile",file.toString());result.put("errorLine",match.group(2));result.put("errorColumn","1");}}catch(InvalidPathException ignored){}}
    result.put("errorSummary",summary.substring(0,Math.min(400,summary.length())));result.put("errorToken",hash(result.toString()));return result;
  }
  private VirtualFile currentFile() {var manager=FileEditorManager.getInstance(project);var editor=manager.getSelectedTextEditor();if(editor!=null)return FileDocumentManager.getInstance().getFile(editor.getDocument());VirtualFile[] files=manager.getSelectedFiles();return files.length==0?null:files[0];}
  private RunnerAndConfigurationSettings currentPython() {
    VirtualFile file=currentFile();if(file==null || !"py".equalsIgnoreCase(file.getExtension()) || !file.isInLocalFileSystem())throw new IllegalStateException("Open a local .py file in PyCharm first.");
    var manager=RunManager.getInstance(project);var config=manager.createConfiguration("Forever Young · "+file.getName(),PythonConfigurationType.getInstance().getFactory());
    var python=(PythonRunConfiguration)config.getConfiguration();var module=ModuleUtilCore.findModuleForFile(file,project);
    var sdk=module==null?ProjectRootManager.getInstance(project).getProjectSdk():PythonSdkUtil.findPythonSdk(module);
    if(sdk==null || !PythonSdkUtil.isPythonSdk(sdk) || PythonSdkUtil.isRemote(sdk))throw new IllegalStateException("Choose the project's existing local Python interpreter in PyCharm.");
    python.setSdk(sdk);python.setUseModuleSdk(false);python.setScriptName(file.getPath());python.setModuleMode(false);python.setScriptParameters("");python.setWorkingDirectory(file.getParent().getPath());
    config.setTemporary(true);config.setEditBeforeRun(false);config.setActivateToolWindowBeforeRun(true);config.setFocusToolWindowBeforeRun(true);return config;
  }
  private void runFile() {
    synchronized(this){if(launchPending || !ownedRuns.isEmpty())throw new IllegalStateException("A current-file run is already active. Stop it or wait for completion.");launchPending=true;lastError=Map.of();phase="preparing";state="working";publish();}
    try {var file=currentFile();var document=file==null?null:FileDocumentManager.getInstance().getDocument(file);if(document!=null)FileDocumentManager.getInstance().saveDocument(document);var config=currentPython();config.checkSettings();ownedConfigs.add(config.getConfiguration());ProgramRunnerUtil.executeConfiguration(config,DefaultRunExecutor.getRunExecutorInstance());}
    catch(Exception e){synchronized(this){launchPending=false;state="failed";phase="failed";lastError=Map.of("errorKind","launch","errorSummary",Objects.toString(e.getMessage(),e.getClass().getSimpleName()));publish();}throw new IllegalStateException(e.getMessage(),e);}
  }
  private static String token(RunnerAndConfigurationSettings config) {
    try {Element xml=new Element("configuration");config.getConfiguration().writeExternal(xml);return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((config.getUniqueID()+JDOMUtil.writeElement(xml)).getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
    catch(Exception error){throw new IllegalStateException("Configuration preview unavailable",error);}
  }
  private RunnerAndConfigurationSettings target(String action) {
    RunManager manager=RunManager.getInstance(project);
    List<RunnerAndConfigurationSettings> configs=manager.getAllSettings().stream().filter(c->!ownedConfigs.contains(c.getConfiguration())).toList();
    if(action.equals("test"))configs=configs.stream().filter(c->c.getType().getId().toLowerCase(Locale.ROOT).contains("test")).toList();
    String saved=PropertiesComponent.getInstance(project).getValue("ForeverYoung.target."+action);
    RunnerAndConfigurationSettings selected=configs.stream().filter(c->c.getUniqueID().equals(saved)).findFirst().orElse(null);
    if(selected==null&&saved==null) {RunnerAndConfigurationSettings current=manager.getSelectedConfiguration();selected=configs.contains(current)?current:configs.size()==1?configs.get(0):null;}
    return selected;
  }
  private void refresh() {
    ApplicationManager.getApplication().invokeLater(()->{
      if(disposed||project.isDisposed())return;
      try {
        Map<String,String> info=new LinkedHashMap<>();info.put("pluginVersion","3.8.0");info.put("bridgeAPI","2");info.put("ideVersion",ApplicationInfo.getInstance().getFullVersion());
        Window window=KeyboardFocusManager.getCurrentKeyboardFocusManager().getFocusedWindow();var frame=WindowManager.getInstance().getFrame(project);boolean focused=frame!=null && window!=null && (window==frame || window.getOwner()==frame);
        if(focused && !wasFocused)focusedAt=System.currentTimeMillis();wasFocused=focused;info.put("focused",Boolean.toString(focused));info.put("focusedAt",Long.toString(focusedAt));
        VirtualFile file=currentFile();info.put("file",file==null?"":file.getPath());info.put("runtime","");info.put("fileToken",hash(info.get("file")));
        try {var current=currentPython();info.put("runtime",Objects.toString(((PythonRunConfiguration)current.getConfiguration()).getSdk().getHomePath(),""));}catch(Exception ignored){}
        for(String action:List.of("run","test")) {RunnerAndConfigurationSettings selected=target(action);info.put(action+"Target",selected==null?"":selected.getName());info.put(action+"Token",selected==null?"select":token(selected));
          if(info.get("runtime").isEmpty()&&action.equals("run")&&selected!=null&&selected.getConfiguration() instanceof AbstractPythonRunConfiguration<?> python) {var sdk=python.getSdk();info.put("runtime",sdk==null?"":Objects.toString(sdk.getHomePath(),""));}}
        synchronized(this){metadata=info;publish();}
      } catch(Exception error){synchronized(this){metadata=Map.of("pluginVersion","3.8.0","diagnosticError",error.getClass().getSimpleName());publish();}}
    });
  }
  private void poll() {
    if(disposed||project.isDisposed())return;
    try(DirectoryStream<Path> files=Files.newDirectoryStream(root.resolve("commands"),instance+"-*.json")) {
      int count=0;
      for(Path file:files) {
        if(++count>100)break;
        if(Files.isSymbolicLink(file)||!Files.isRegularFile(file)||Files.size(file)>4096)continue;
        try {
        JsonObject value=gson.fromJson(Files.readString(file),JsonObject.class);
        String id=value.get("id").getAsString(),action=value.get("action").getAsString();
        if(value.get("version").getAsInt()!=1||!value.get("instance").getAsString().equals(instance)||!value.get("source").getAsString().equals("pycharm")||!List.of("run","chooseRun","runFile","test","stop","openProblems","openConsole","openError").contains(action)||Math.abs(System.currentTimeMillis()-value.get("sentAt").getAsLong())>15000) {Files.deleteIfExists(file);continue;}
        UUID.fromString(id);Files.deleteIfExists(file);if(!seen.add(id))continue;
        ApplicationManager.getApplication().invokeLater(()->{
          if(disposed||project.isDisposed())return;
          try {command(action,value.has("expectedToken")?value.get("expectedToken").getAsString():null);refresh();write("acks",id,Map.of("version",1,"id",id,"ok",true));}
          catch(Exception error){try{write("acks",id,Map.of("version",1,"id",id,"ok",false,"error",Objects.toString(error.getMessage(),error.getClass().getSimpleName()).substring(0,Math.min(400,Objects.toString(error.getMessage(),error.getClass().getSimpleName()).length()))));}catch(Exception ignored){}}
        });
        } catch(Exception invalid) {Files.deleteIfExists(file);}
      }
    } catch(Exception ignored){}
  }
  private void command(String action,String expectedToken) {
    if(action.equals("openError")){if(expectedToken==null || !expectedToken.equals(lastError.get("errorToken")))throw new IllegalStateException("The error changed. Refresh before opening it.");String file=lastError.get("errorFile");if(file==null){command("openConsole",null);return;}VirtualFile target=LocalFileSystem.getInstance().findFileByPath(file);if(target!=null)new OpenFileDescriptor(project,target,Math.max(0,Integer.parseInt(lastError.getOrDefault("errorLine","1"))-1),0).navigate(true);return;}
    if(action.equals("runFile")){VirtualFile file=currentFile();String current=hash(file==null?"":file.getPath());if(expectedToken!=null&&!current.equals(expectedToken))throw new IllegalStateException("Current file changed. Refresh the pet preview.");runFile();return;}

    if(action.equals("openProblems")||action.equals("openConsole")) {
      ToolWindowManager manager=ToolWindowManager.getInstance(project);String id=action.equals("openProblems")?"Problems View":"Run";
      manager.invokeLater(()->{var window=manager.getToolWindow(id);if(window!=null)window.activate(null);else Messages.showInfoMessage(project,"This panel is not available yet. Run the project first.","Forever Young");});return;
    }
    if(expectedToken!=null&&!action.equals("stop")&&!action.equals("chooseRun")) {
      var selected=target(action);String current=selected==null?"select":token(selected);
      if(!current.equals(expectedToken)) {Messages.showInfoMessage(project,"Run target changed. Refresh the pet preview before running.","Forever Young");throw new IllegalStateException("Run target changed");}
    }
    if(action.equals("stop")) {
      List<ProcessHandler> handlers; synchronized(this){handlers=new ArrayList<>(active.values());}
      if(handlers.isEmpty())return;
      List<ProcessHandler> owned;synchronized(this){owned=ownedRuns.stream().map(active::get).filter(Objects::nonNull).toList();}
      if(!owned.isEmpty()){owned.forEach(ProcessHandler::destroyProcess);return;}
      if(handlers.size()==1){handlers.get(0).destroyProcess();return;}
      if(Messages.showYesNoDialog(project,"Stop the "+handlers.size()+" running process(es) in this project?","Forever Young",Messages.getQuestionIcon())==Messages.YES)handlers.forEach(ProcessHandler::destroyProcess);
      return;
    }
    RunManager manager=RunManager.getInstance(project);
    List<RunnerAndConfigurationSettings> configs=manager.getAllSettings().stream().filter(c->!ownedConfigs.contains(c.getConfiguration())).toList();
    if(action.equals("test"))configs=configs.stream().filter(c->c.getType().getId().toLowerCase(Locale.ROOT).contains("test")).toList();
    if(configs.isEmpty()){Messages.showInfoMessage(project,"Create a saved Run/Debug configuration first.","Forever Young");return;}
    PropertiesComponent preferences=PropertiesComponent.getInstance(project);
    String preference="ForeverYoung.target."+(action.equals("test")?"test":"run");
    String saved=preferences.getValue(preference);
    RunnerAndConfigurationSettings selected=action.equals("chooseRun")?null:configs.stream().filter(c->c.getUniqueID().equals(saved)).findFirst().orElse(null);
    if(selected==null&&saved==null&&!action.equals("chooseRun")) {
      RunnerAndConfigurationSettings current=manager.getSelectedConfiguration();
      selected=configs.contains(current)?current:configs.size()==1?configs.get(0):null;
    }
    if(selected==null) {
      JBPopupFactory.getInstance().createPopupChooserBuilder(configs)
        .setTitle("Forever Young · Select run target")
        .setRequestFocus(true)
        .setRenderer((list,value,index,isSelected,hasFocus)->new DefaultListCellRenderer().getListCellRendererComponent(list,value.getName(),index,isSelected,hasFocus))
        .setNamerForFiltering(RunnerAndConfigurationSettings::getName)
        .setItemChosenCallback(choice->executeSelected(action,preference,choice))
        .createPopup().showCenteredInCurrentWindow(project);
      return;
    }
    executeSelected(action,preference,selected);
  }
  private void executeSelected(String action,String preference,RunnerAndConfigurationSettings selected) {
    if(disposed||project.isDisposed())return;
    PropertiesComponent.getInstance(project).setValue(preference,selected.getUniqueID());
    if(action.equals("chooseRun")){refresh();return;}
    synchronized(this){if(!active.isEmpty() || launchPending)throw new IllegalStateException("A project process is already running. Stop it or wait.");launchPending=true;ownedConfigs.add(selected.getConfiguration());lastError=Map.of();state="working";phase="preparing";publish();}
    try{ProgramRunnerUtil.executeConfiguration(selected,DefaultRunExecutor.getRunExecutorInstance());}
    catch(RuntimeException e){synchronized(this){launchPending=false;ownedConfigs.remove(selected.getConfiguration());state="failed";phase="failed";lastError=Map.of("errorKind","launch","errorSummary",Objects.toString(e.getMessage(),e.getClass().getSimpleName()));publish();}throw e;}
  }
  @Override public synchronized void dispose(){disposed=true;timer.shutdownNow();try{Files.deleteIfExists(root.resolve("events").resolve(instance+".json"));}catch(Exception ignored){}synchronized(PetBridge.class){INSTANCES.remove(project);}}
}
