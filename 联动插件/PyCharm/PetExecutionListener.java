package org.foreveryoungpet.bridge;
import com.intellij.execution.ExecutionListener;
import com.intellij.execution.runners.ExecutionEnvironment;
import com.intellij.execution.process.ProcessHandler;
import org.jetbrains.annotations.NotNull;
public final class PetExecutionListener implements ExecutionListener {
  @Override public void processStarted(@NotNull String executorId,@NotNull ExecutionEnvironment environment,@NotNull ProcessHandler handler) {
    PetBridge.get(environment.getProject()).started(environment,handler);
  }
  @Override public void processTerminated(@NotNull String executorId,@NotNull ExecutionEnvironment environment,@NotNull ProcessHandler handler,int exitCode) {
    PetBridge.get(environment.getProject()).ended(environment,handler,exitCode);
  }
  @Override public void processNotStarted(@NotNull String executorId,@NotNull ExecutionEnvironment environment) {
    PetBridge.get(environment.getProject()).ended(environment,null,-1);
  }
}
