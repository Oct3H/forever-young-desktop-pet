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
  private Map<String,String> metadata=Map.of("pluginVersion","3.7.0");
  private volatile boolean disposed=false;
  private PetBridge(Project project) {
    this.project=project;title=project.getName();Disposer.register(project,this);
    try {for(String folder:List.of("events","commands","acks")){Path p=root.resolve(folder);Files.createDirectories(p);Files.setPosixFilePermissions(p,PosixFilePermissions.fromString("rwx------"));}}
    catch(Exception ignored){return;}
    refresh();timer.scheduleAtFixedRate(this::refresh,2,2,TimeUnit.SECONDS);timer.scheduleWithFixedDelay(this::poll,500,500,TimeUnit.MILLISECONDS);
  }
  synchronized void started(ExecutionEnvironment environment,ProcessHandler handler) {
    active.put(environment.getExecutionId(),handler);state="working";runID=Long.toString(environment.getExecutionId());title=environment.getRunProfile().getName();publish();
  }
  synchronized void ended(ExecutionEnvironment environment,ProcessHandler handler,int code) {
    active.remove(environment.getExecutionId());state=code==0?"completed":code==130||code==143?"interrupted":"failed";
    runID=Long.toString(environment.getExecutionId());title=environment.getRunProfile().getName();publish();
  }
  private void write(String folder,String name,Object data)throws Exception {
    Path target=root.resolve(folder).resolve(name+".json"),temp=root.resolve(folder).resolve(name+".tmp");
    Files.writeString(temp,gson.toJson(data));Files.setPosixFilePermissions(temp,PosixFilePermissions.fromString("rw-------"));Files.move(temp,target,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
  }
  private synchronized void publish() {
    if(disposed)return;
    try {Map<String,Object> event=new LinkedHashMap<>();event.put("version",1);event.put("source","pycharm");event.put("instance",instance);event.put("sequence",++sequence);event.put("sentAt",System.currentTimeMillis());event.put("state",state);event.put("runID",runID);event.put("title",title.length()>500?title.substring(0,500):title);event.put("project",Objects.toString(project.getBasePath(),""));event.put("activeCount",active.size());event.put("actions",List.of("run","chooseRun","test","stop","openProblems","openConsole"));event.put("metadata",metadata);write("events",instance,event);}
    catch(Exception ignored){} // No project output or credentials are logged.
  }
  private static String token(RunnerAndConfigurationSettings config) {
    try {Element xml=new Element("configuration");config.getConfiguration().writeExternal(xml);return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest((config.getUniqueID()+JDOMUtil.writeElement(xml)).getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
    catch(Exception error){throw new IllegalStateException("Configuration preview unavailable",error);}
  }
  private RunnerAndConfigurationSettings target(String action) {
    RunManager manager=RunManager.getInstance(project);
    List<RunnerAndConfigurationSettings> configs=manager.getAllSettings();
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
        Map<String,String> info=new LinkedHashMap<>();info.put("pluginVersion","3.7.0");info.put("ideVersion",ApplicationInfo.getInstance().getFullVersion());
        VirtualFile[] files=FileEditorManager.getInstance(project).getSelectedFiles();info.put("file",files.length>0?files[0].getPath():"");info.put("runtime","");
        for(String action:List.of("run","test")) {RunnerAndConfigurationSettings selected=target(action);info.put(action+"Target",selected==null?"":selected.getName());info.put(action+"Token",selected==null?"select":token(selected));
          if(action.equals("run")&&selected!=null&&selected.getConfiguration() instanceof AbstractPythonRunConfiguration<?> python) {var sdk=python.getSdk();info.put("runtime",sdk==null?"":Objects.toString(sdk.getHomePath(),""));}}
        synchronized(this){metadata=info;publish();}
      } catch(Exception error){synchronized(this){metadata=Map.of("pluginVersion","3.7.0","diagnosticError",error.getClass().getSimpleName());publish();}}
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
        if(value.get("version").getAsInt()!=1||!value.get("instance").getAsString().equals(instance)||!value.get("source").getAsString().equals("pycharm")||!List.of("run","chooseRun","test","stop","openProblems","openConsole").contains(action)||Math.abs(System.currentTimeMillis()-value.get("sentAt").getAsLong())>15000) {Files.deleteIfExists(file);continue;}
        UUID.fromString(id);Files.deleteIfExists(file);if(!seen.add(id))continue;
        ApplicationManager.getApplication().invokeLater(()->{
          if(disposed||project.isDisposed())return;
          try {command(action,value.has("expectedToken")?value.get("expectedToken").getAsString():null);refresh();write("acks",id,Map.of("version",1,"id",id,"ok",true));}
          catch(Exception error){try{write("acks",id,Map.of("version",1,"id",id,"ok",false,"error",error.getClass().getSimpleName()));}catch(Exception ignored){}}
        });
        } catch(Exception invalid) {Files.deleteIfExists(file);}
      }
    } catch(Exception ignored){}
  }
  private void command(String action,String expectedToken) {
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
      if(Messages.showYesNoDialog(project,"Stop the "+handlers.size()+" running process(es) in this project?","Forever Young",Messages.getQuestionIcon())==Messages.YES)handlers.forEach(ProcessHandler::destroyProcess);
      return;
    }
    RunManager manager=RunManager.getInstance(project);
    List<RunnerAndConfigurationSettings> configs=manager.getAllSettings();
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
    ProgramRunnerUtil.executeConfiguration(selected,DefaultRunExecutor.getRunExecutorInstance());
  }
  @Override public synchronized void dispose(){disposed=true;timer.shutdownNow();try{Files.deleteIfExists(root.resolve("events").resolve(instance+".json"));}catch(Exception ignored){}synchronized(PetBridge.class){INSTANCES.remove(project);}}
}
