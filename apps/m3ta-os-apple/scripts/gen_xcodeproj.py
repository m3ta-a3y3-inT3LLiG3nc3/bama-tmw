#!/usr/bin/env python3
"""Generates BAMA.xcodeproj (objectVersion 77, file-system-synchronized folders). No third-party tools."""
import hashlib, os
H=lambda *k: hashlib.md5("/".join(k).encode()).hexdigest()[:24].upper()
O={}
def obj(i, d): O[i]=d; return i
def q(v):
    if isinstance(v,list): return "("+"".join(q(x)+", " for x in v)+")"
    if isinstance(v,dict): return "{"+"".join(f"{q(k)} = {q(x)}; " for k,x in v.items())+"}"
    s=str(v)
    return s if s.replace("_","").replace(".","").replace("/","").isalnum() and s else '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
pkg=obj(H("pkg"),{"isa":"XCLocalSwiftPackageReference","relativePath":"../m3ta-os-console"})
groups={}
def sync(path):
    if path not in groups: groups[path]=obj(H("g",path),{"isa":"PBXFileSystemSynchronizedRootGroup","path":path,"sourceTree":"<group>"})
    return groups[path]
COMMON={"SWIFT_VERSION":"6.0","CODE_SIGN_STYLE":"Automatic","DEVELOPMENT_TEAM":"$(BAMA_TEAM)","MARKETING_VERSION":"0.1.0","CURRENT_PROJECT_VERSION":"1","GENERATE_INFOPLIST_FILE":"YES","ENABLE_PREVIEWS":"YES","SWIFT_EMIT_LOC_STRINGS":"YES"}
T=[
 dict(n="BAMA",type="com.apple.product-type.application",ext="app",dirs=["Shared","iOS"],embed=["BAMAWidgets"],s={"SDKROOT":"iphoneos","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","TARGETED_DEVICE_FAMILY":"1,2","IPHONEOS_DEPLOYMENT_TARGET":"26.0","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX)","INFOPLIST_KEY_CFBundleDisplayName":"BAMA","INFOPLIST_KEY_NSFaceIDUsageDescription":"Face ID confirms JEV approvals.","INFOPLIST_KEY_NSSupportsLiveActivities":"YES","INFOPLIST_KEY_UILaunchScreen_Generation":"YES","INFOPLIST_KEY_UIApplicationSceneManifest_Generation":"YES","INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad":"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks"}),
 dict(n="BAMAWidgets",type="com.apple.product-type.app-extension",ext="appex",dirs=["Shared","iOSWidgets"],s={"SDKROOT":"iphoneos","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator","TARGETED_DEVICE_FAMILY":"1,2","IPHONEOS_DEPLOYMENT_TARGET":"26.0","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX).widgets","INFOPLIST_FILE":"Config/Widgets-Info.plist","SKIP_INSTALL":"YES","APPLICATION_EXTENSION_API_ONLY":"YES","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"}),
 dict(n="BAMAWatch",type="com.apple.product-type.application",ext="app",dirs=["Shared","Watch"],embed=["BAMAWatchWidgets"],s={"SDKROOT":"watchos","SUPPORTED_PLATFORMS":"watchos watchsimulator","TARGETED_DEVICE_FAMILY":"4","WATCHOS_DEPLOYMENT_TARGET":"26.0","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX).watchkitapp","INFOPLIST_KEY_CFBundleDisplayName":"BAMA","INFOPLIST_KEY_WKWatchOnly":"YES","INFOPLIST_KEY_WKApplication":"YES","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks"}),
 dict(n="BAMAWatchWidgets",type="com.apple.product-type.app-extension",ext="appex",dirs=["Shared","WatchWidgets"],s={"SDKROOT":"watchos","SUPPORTED_PLATFORMS":"watchos watchsimulator","TARGETED_DEVICE_FAMILY":"4","WATCHOS_DEPLOYMENT_TARGET":"26.0","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX).watchkitapp.widgets","INFOPLIST_FILE":"Config/WatchWidgets-Info.plist","SKIP_INSTALL":"YES","APPLICATION_EXTENSION_API_ONLY":"YES","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"}),
 dict(n="BAMAMac",type="com.apple.product-type.application",ext="app",dirs=["../m3ta-os-console/Sources/M3taOSConsole"],s={"SDKROOT":"macosx","SUPPORTED_PLATFORMS":"macosx","MACOSX_DEPLOYMENT_TARGET":"26.0","PRODUCT_NAME":"M3ta-OS Console","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX).mac","ENABLE_HARDENED_RUNTIME":"YES","INFOPLIST_KEY_LSApplicationCategoryType":"public.app-category.productivity","INFOPLIST_KEY_CFBundleDisplayName":"M3ta-OS Console","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/../Frameworks"}),
 dict(n="BAMATests",type="com.apple.product-type.bundle.unit-test",ext="xctest",dirs=["Tests"],s={"SDKROOT":"iphoneos","SUPPORTED_PLATFORMS":"iphoneos iphonesimulator macosx","SUPPORTS_MACCATALYST":"NO","IPHONEOS_DEPLOYMENT_TARGET":"26.0","MACOSX_DEPLOYMENT_TARGET":"26.0","PRODUCT_BUNDLE_IDENTIFIER":"$(BAMA_BUNDLE_PREFIX).tests","TARGETED_DEVICE_FAMILY":"1,2"}),
]
xcfg=obj(H("xcconfig"),{"isa":"PBXFileReference","lastKnownFileType":"text.xcconfig","path":"Config/Signing.xcconfig","sourceTree":"<group>"})
prod={}; tid={}
for t in T:
    prod[t["n"]]=obj(H("prod",t["n"]),{"isa":"PBXFileReference","explicitFileType":{"app":"wrapper.application","appex":"wrapper.app-extension","xctest":"wrapper.cfbundle"}[t["ext"]],"includeInIndex":"0","path":(t["s"].get("PRODUCT_NAME",t["n"]))+"."+t["ext"],"sourceTree":"BUILT_PRODUCTS_DIR"})
    tid[t["n"]]=H("target",t["n"])
def cfgs(owner, base, extra=None):
    l=[]
    for c in ["Debug","Release"]:
        s=dict(base)
        if extra: s.update(extra)
        if c=="Debug": s.update({"SWIFT_OPTIMIZATION_LEVEL":"-Onone","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG $(inherited)","ONLY_ACTIVE_ARCH":"YES","DEBUG_INFORMATION_FORMAT":"dwarf"} if owner=="proj" else {})
        d={"isa":"XCBuildConfiguration","buildSettings":s,"name":c}
        if owner=="proj": d["baseConfigurationReference"]=xcfg
        l.append(obj(H("cfg",owner,c),d))
    return obj(H("cfglist",owner),{"isa":"XCConfigurationList","buildConfigurations":l,"defaultConfigurationIsVisible":"0","defaultConfigurationName":"Release"})
for t in T:
    n=t["n"]
    dep=obj(H("pd",n),{"isa":"XCSwiftPackageProductDependency","package":pkg,"productName":"ConsoleCore"})
    bf=obj(H("bfpkg",n),{"isa":"PBXBuildFile","productRef":dep})
    phases=[obj(H("src",n),{"isa":"PBXSourcesBuildPhase","buildActionMask":"2147483647","files":[],"runOnlyForDeploymentPostprocessing":"0"}),
            obj(H("fw",n),{"isa":"PBXFrameworksBuildPhase","buildActionMask":"2147483647","files":[bf],"runOnlyForDeploymentPostprocessing":"0"}),
            obj(H("res",n),{"isa":"PBXResourcesBuildPhase","buildActionMask":"2147483647","files":[],"runOnlyForDeploymentPostprocessing":"0"})]
    deps=[]
    for e in t.get("embed",[]):
        px=obj(H("proxy",n,e),{"isa":"PBXContainerItemProxy","containerPortal":H("project"),"proxyType":"1","remoteGlobalIDString":tid[e],"remoteInfo":e})
        deps.append(obj(H("dep",n,e),{"isa":"PBXTargetDependency","target":tid[e],"targetProxy":px}))
        eb=obj(H("embf",n,e),{"isa":"PBXBuildFile","fileRef":prod[e],"settings":{"ATTRIBUTES":["RemoveHeadersOnCopy"]}})
        phases.append(obj(H("emb",n,e),{"isa":"PBXCopyFilesBuildPhase","buildActionMask":"2147483647","dstPath":"","dstSubfolderSpec":"13","files":[eb],"name":"Embed Foundation Extensions","runOnlyForDeploymentPostprocessing":"0"}))
    s=dict(COMMON); s.update(t["s"]); s.setdefault("PRODUCT_NAME","$(TARGET_NAME)")
    O[tid[n]]={"isa":"PBXNativeTarget","buildConfigurationList":cfgs(n,s),"buildPhases":phases,"buildRules":[],"dependencies":deps,
        "fileSystemSynchronizedGroups":[sync(d) for d in t["dirs"]],"name":n,"packageProductDependencies":[dep],"productName":n,"productReference":prod[n],"productType":t["type"]}
pg=obj(H("productsgroup"),{"isa":"PBXGroup","children":list(prod.values()),"name":"Products","sourceTree":"<group>"})
main=obj(H("main"),{"isa":"PBXGroup","children":[xcfg]+list(groups.values())+[pg],"sourceTree":"<group>"})
O[H("project")]={"isa":"PBXProject","attributes":{"BuildIndependentTargetsInParallel":"1","LastSwiftUpdateCheck":"2710","LastUpgradeCheck":"2710"},
  "buildConfigurationList":cfgs("proj",{"CLANG_ENABLE_MODULES":"YES","ENABLE_STRICT_OBJC_MSGSEND":"YES","ENABLE_USER_SCRIPT_SANDBOXING":"YES","GCC_C_LANGUAGE_STANDARD":"gnu17","LOCALIZATION_PREFERS_STRING_CATALOGS":"YES","SWIFT_VERSION":"6.0"}),
  "compatibilityVersion":"Xcode 15.3","developmentRegion":"en","hasScannedForEncodings":"0","knownRegions":["en","Base"],"mainGroup":main,"minimizedProjectReferenceProxies":"1",
  "packageReferences":[pkg],"preferredProjectObjectVersion":"77","productRefGroup":pg,"projectDirPath":"","projectRoot":"","targets":[tid[t["n"]] for t in T]}
out="// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n"
for k in sorted(O): out+=f"\t\t{k} = {q(O[k])};\n"
out+=f"\t}};\n\trootObject = {H('project')};\n}}\n"
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(f"{root}/BAMA.xcodeproj",exist_ok=True); open(f"{root}/BAMA.xcodeproj/project.pbxproj","w").write(out); print("wrote", len(O), "objects")
