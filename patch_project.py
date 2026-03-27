#!/usr/bin/env python3
"""Patch Folder.xcodeproj/project.pbxproj to add FolderShare extension target."""

import shutil
import subprocess

PROJECT_PATH = "/Users/bartbak/Repo/FolderApp/Folder/Folder.xcodeproj/project.pbxproj"
BACKUP_PATH = PROJECT_PATH + ".bak"

# Back up the original
shutil.copy2(PROJECT_PATH, BACKUP_PATH)
print(f"Backed up to {BACKUP_PATH}")

with open(PROJECT_PATH, "r") as f:
    content = f.read()

def replace_once(content, old, new, label):
    assert old in content, f"Could not find: {label}"
    return content.replace(old, new, 1)

# -------------------------------------------------------------------------
# 1. PBXBuildFile section — add embed build file entry
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXBuildFile section */",
    "\t\tBB00000A2F755D9A00FB6AEE /* FolderShare.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = BB0000012F755D9A00FB6AEE /* FolderShare.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };\n/* End PBXBuildFile section */",
    "PBXBuildFile section end"
)

# -------------------------------------------------------------------------
# 2. PBXContainerItemProxy section — add proxy for FolderShare
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXContainerItemProxy section */",
    "\t\tBB00000C2F755D9A00FB6AEE /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = 5EA1306E2F755D9A00FB6AEE /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = BB0000062F755D9A00FB6AEE;\n\t\t\tremoteInfo = FolderShare;\n\t\t};\n/* End PBXContainerItemProxy section */",
    "PBXContainerItemProxy section end"
)

# -------------------------------------------------------------------------
# 3. PBXCopyFilesBuildPhase section — insert before PBXFileReference
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* Begin PBXFileReference section */",
    "/* Begin PBXCopyFilesBuildPhase section */\n\t\tBB00000B2F755D9A00FB6AEE /* Embed Foundation Extensions */ = {\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\tBB00000A2F755D9A00FB6AEE /* FolderShare.appex in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXCopyFilesBuildPhase section */\n\n/* Begin PBXFileReference section */",
    "PBXFileReference section start"
)

# -------------------------------------------------------------------------
# 4. PBXFileReference section — add FolderShare.appex reference
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXFileReference section */",
    "\t\tBB0000012F755D9A00FB6AEE /* FolderShare.appex */ = {isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = FolderShare.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n/* End PBXFileReference section */",
    "PBXFileReference section end"
)

# -------------------------------------------------------------------------
# 5. PBXFileSystemSynchronizedRootGroup section — add FolderShare group
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXFileSystemSynchronizedRootGroup section */",
    "\t\tBB0000022F755D9A00FB6AEE /* FolderShare */ = {\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = FolderShare;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n/* End PBXFileSystemSynchronizedRootGroup section */",
    "PBXFileSystemSynchronizedRootGroup section end"
)

# -------------------------------------------------------------------------
# 6. PBXFrameworksBuildPhase section — add FolderShare's frameworks phase
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXFrameworksBuildPhase section */",
    "\t\tBB0000042F755D9A00FB6AEE /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXFrameworksBuildPhase section */",
    "PBXFrameworksBuildPhase section end"
)

# -------------------------------------------------------------------------
# 7. PBXGroup (root group) — add FolderShare sync group to children
# -------------------------------------------------------------------------
content = replace_once(content,
    "\t\t\t\t5EA130782F755D9A00FB6AEE /* Folder */,\n\t\t\t\t5EA130882F755D9C00FB6AEE /* FolderTests */,",
    "\t\t\t\t5EA130782F755D9A00FB6AEE /* Folder */,\n\t\t\t\tBB0000022F755D9A00FB6AEE /* FolderShare */,\n\t\t\t\t5EA130882F755D9C00FB6AEE /* FolderTests */,",
    "root group children"
)

# -------------------------------------------------------------------------
# 8. PBXGroup (Products) — add FolderShare.appex to children
# -------------------------------------------------------------------------
content = replace_once(content,
    "\t\t\t\t5EA130762F755D9A00FB6AEE /* Folder.app */,\n\t\t\t\t5EA130852F755D9C00FB6AEE /* FolderTests.xctest */,",
    "\t\t\t\t5EA130762F755D9A00FB6AEE /* Folder.app */,\n\t\t\t\tBB0000012F755D9A00FB6AEE /* FolderShare.appex */,\n\t\t\t\t5EA130852F755D9C00FB6AEE /* FolderTests.xctest */,",
    "Products group children"
)

# -------------------------------------------------------------------------
# 9. PBXNativeTarget section — add FolderShare target
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXNativeTarget section */",
    "\t\tBB0000062F755D9A00FB6AEE /* FolderShare */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = BB0000092F755D9A00FB6AEE /* Build configuration list for PBXNativeTarget \"FolderShare\" */;\n\t\t\tbuildPhases = (\n\t\t\t\tBB0000032F755D9A00FB6AEE /* Sources */,\n\t\t\t\tBB0000042F755D9A00FB6AEE /* Frameworks */,\n\t\t\t\tBB0000052F755D9A00FB6AEE /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\tBB0000022F755D9A00FB6AEE /* FolderShare */,\n\t\t\t);\n\t\t\tname = FolderShare;\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = FolderShare;\n\t\t\tproductReference = BB0000012F755D9A00FB6AEE /* FolderShare.appex */;\n\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t};\n/* End PBXNativeTarget section */",
    "PBXNativeTarget section end"
)

# -------------------------------------------------------------------------
# 10. PBXNativeTarget (Folder target) — add embed phase to buildPhases, add dependency
# -------------------------------------------------------------------------
content = replace_once(content,
    "\t\t\t\t5EA130722F755D9A00FB6AEE /* Sources */,\n\t\t\t\t5EA130732F755D9A00FB6AEE /* Frameworks */,\n\t\t\t\t5EA130742F755D9A00FB6AEE /* Resources */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);",
    "\t\t\t\t5EA130722F755D9A00FB6AEE /* Sources */,\n\t\t\t\t5EA130732F755D9A00FB6AEE /* Frameworks */,\n\t\t\t\t5EA130742F755D9A00FB6AEE /* Resources */,\n\t\t\t\tBB00000B2F755D9A00FB6AEE /* Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t\tBB00000D2F755D9A00FB6AEE /* PBXTargetDependency */,\n\t\t\t);",
    "Folder target buildPhases"
)

# -------------------------------------------------------------------------
# 11a. PBXProject — add FolderShare to targets list
# -------------------------------------------------------------------------
content = replace_once(content,
    "\t\t\t\t5EA130752F755D9A00FB6AEE /* Folder */,\n\t\t\t\t5EA130842F755D9C00FB6AEE /* FolderTests */,",
    "\t\t\t\t5EA130752F755D9A00FB6AEE /* Folder */,\n\t\t\t\tBB0000062F755D9A00FB6AEE /* FolderShare */,\n\t\t\t\t5EA130842F755D9C00FB6AEE /* FolderTests */,",
    "targets list in PBXProject"
)

# -------------------------------------------------------------------------
# 11b. PBXProject — add TargetAttributes entry for FolderShare
# Use the exact whitespace (5 tabs) from the file
# -------------------------------------------------------------------------
content = replace_once(content,
    "\t\t\t\t\t5EA1308E2F755D9C00FB6AEE = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t\tTestTargetID = 5EA130752F755D9A00FB6AEE;\n\t\t\t\t\t};\n\t\t\t\t};",
    "\t\t\t\t\t5EA1308E2F755D9C00FB6AEE = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t\tTestTargetID = 5EA130752F755D9A00FB6AEE;\n\t\t\t\t\t};\n\t\t\t\t\tBB0000062F755D9A00FB6AEE = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t};\n\t\t\t\t};",
    "TargetAttributes end"
)

# -------------------------------------------------------------------------
# 12. PBXResourcesBuildPhase section — add FolderShare's resources phase
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXResourcesBuildPhase section */",
    "\t\tBB0000052F755D9A00FB6AEE /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXResourcesBuildPhase section */",
    "PBXResourcesBuildPhase section end"
)

# -------------------------------------------------------------------------
# 13. PBXSourcesBuildPhase section — add FolderShare's sources phase
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXSourcesBuildPhase section */",
    "\t\tBB0000032F755D9A00FB6AEE /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n/* End PBXSourcesBuildPhase section */",
    "PBXSourcesBuildPhase section end"
)

# -------------------------------------------------------------------------
# 14. PBXTargetDependency section — add dependency
# -------------------------------------------------------------------------
content = replace_once(content,
    "/* End PBXTargetDependency section */",
    "\t\tBB00000D2F755D9A00FB6AEE /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = BB0000062F755D9A00FB6AEE /* FolderShare */;\n\t\t\ttargetProxy = BB00000C2F755D9A00FB6AEE /* PBXContainerItemProxy */;\n\t\t};\n/* End PBXTargetDependency section */",
    "PBXTargetDependency section end"
)

# -------------------------------------------------------------------------
# 15. XCBuildConfiguration section — add Debug and Release configs for FolderShare
# -------------------------------------------------------------------------
foldershare_debug = (
    "\t\tBB0000072F755D9A00FB6AEE /* Debug */ = {\n"
    "\t\t\tisa = XCBuildConfiguration;\n"
    "\t\t\tbuildSettings = {\n"
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
    "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
    "\t\t\t\tDEVELOPMENT_TEAM = TJ3ALYQV5G;\n"
    "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
    "\t\t\t\tINFOPLIST_FILE = FolderShare/Info.plist;\n"
    "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.2;\n"
    "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
    "\t\t\t\t\t\"$(inherited)\",\n"
    "\t\t\t\t\t\"@executable_path/Frameworks\",\n"
    "\t\t\t\t\t\"@executable_path/../../Frameworks\",\n"
    "\t\t\t\t);\n"
    "\t\t\t\tMARKETING_VERSION = 1.0;\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.bartbak.fastapp.Folder.FolderShare;\n"
    "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
    "\t\t\t\tSKIP_INSTALL = YES;\n"
    "\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n"
    "\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;\n"
    "\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;\n"
    "\t\t\t\tSWIFT_VERSION = 5.0;\n"
    "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
    "\t\t\t};\n"
    "\t\t\tname = Debug;\n"
    "\t\t};\n"
)
foldershare_release = (
    "\t\tBB0000082F755D9A00FB6AEE /* Release */ = {\n"
    "\t\t\tisa = XCBuildConfiguration;\n"
    "\t\t\tbuildSettings = {\n"
    "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
    "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
    "\t\t\t\tDEVELOPMENT_TEAM = TJ3ALYQV5G;\n"
    "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
    "\t\t\t\tINFOPLIST_FILE = FolderShare/Info.plist;\n"
    "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.2;\n"
    "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
    "\t\t\t\t\t\"$(inherited)\",\n"
    "\t\t\t\t\t\"@executable_path/Frameworks\",\n"
    "\t\t\t\t\t\"@executable_path/../../Frameworks\",\n"
    "\t\t\t\t);\n"
    "\t\t\t\tMARKETING_VERSION = 1.0;\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.bartbak.fastapp.Folder.FolderShare;\n"
    "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
    "\t\t\t\tSKIP_INSTALL = YES;\n"
    "\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;\n"
    "\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;\n"
    "\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;\n"
    "\t\t\t\tSWIFT_VERSION = 5.0;\n"
    "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
    "\t\t\t};\n"
    "\t\t\tname = Release;\n"
    "\t\t};\n"
)
content = replace_once(content,
    "/* End XCBuildConfiguration section */",
    foldershare_debug + foldershare_release + "/* End XCBuildConfiguration section */",
    "XCBuildConfiguration section end"
)

# -------------------------------------------------------------------------
# 16. XCConfigurationList section — add config list for FolderShare
# -------------------------------------------------------------------------
foldershare_configlist = (
    "\t\tBB0000092F755D9A00FB6AEE /* Build configuration list for PBXNativeTarget \"FolderShare\" */ = {\n"
    "\t\t\tisa = XCConfigurationList;\n"
    "\t\t\tbuildConfigurations = (\n"
    "\t\t\t\tBB0000072F755D9A00FB6AEE /* Debug */,\n"
    "\t\t\t\tBB0000082F755D9A00FB6AEE /* Release */,\n"
    "\t\t\t);\n"
    "\t\t\tdefaultConfigurationIsVisible = 0;\n"
    "\t\t\tdefaultConfigurationName = Release;\n"
    "\t\t};\n"
)
content = replace_once(content,
    "/* End XCConfigurationList section */",
    foldershare_configlist + "/* End XCConfigurationList section */",
    "XCConfigurationList section end"
)

# Write the modified content back
with open(PROJECT_PATH, "w") as f:
    f.write(content)

print("Project file patched successfully.")

# Verify by trying to parse with plutil
result = subprocess.run(
    ["plutil", "-lint", PROJECT_PATH],
    capture_output=True, text=True
)
print(f"plutil exit code: {result.returncode}")
if result.stdout:
    print(f"stdout: {result.stdout}")
if result.stderr:
    print(f"stderr: {result.stderr}")
if result.returncode != 0:
    print("ERROR: project file is not valid! Restoring backup...")
    shutil.copy2(BACKUP_PATH, PROJECT_PATH)
    print("Backup restored.")
else:
    print("Project file is valid.")
