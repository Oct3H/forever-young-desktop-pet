package org.foreveryoungpet.bridge;
import com.intellij.openapi.project.Project;
import com.intellij.openapi.startup.StartupActivity;
import org.jetbrains.annotations.NotNull;
public final class PetStartup implements StartupActivity.DumbAware {
  @Override public void runActivity(@NotNull Project project) { PetBridge.get(project); }
}
