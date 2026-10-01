#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "xcodeproj"

ROOT = Pathname(__dir__).parent.expand_path
PROJECT_PATH = ROOT / "CellCap.xcodeproj"
MARKETING_VERSION = "1.0.0"
CURRENT_PROJECT_VERSION = "1"

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"
project.root_object.development_region = "ko"

sources_group = project.main_group.new_group("Sources", "Sources")
tests_group = project.main_group.new_group("Tests", "Tests")
docs_group = project.main_group.new_group("Docs")
docs_group.new_file("../README.md")

def configure_build_settings(target, bundle_id: nil, generate_info_plist: true, enable_code_signing: false)
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings["MACOSX_DEPLOYMENT_TARGET"] = "26.0"
    settings["SDKROOT"] = "macosx"
    settings["SWIFT_VERSION"] = "6.0"
    settings["SWIFT_STRICT_CONCURRENCY"] = "complete"
    settings["CODE_SIGNING_ALLOWED"] = enable_code_signing ? "YES" : "NO"
    settings["ENABLE_HARDENED_RUNTIME"] = "NO"
    settings["CLANG_ENABLE_MODULES"] = "YES"

    if enable_code_signing
      settings["CODE_SIGN_STYLE"] = "Automatic"
    else
      settings.delete("CODE_SIGN_STYLE")
    end

    if generate_info_plist
      settings["GENERATE_INFOPLIST_FILE"] = "YES"
      settings["MARKETING_VERSION"] = MARKETING_VERSION
      settings["CURRENT_PROJECT_VERSION"] = CURRENT_PROJECT_VERSION
      settings["INFOPLIST_KEY_CFBundleShortVersionString"] = MARKETING_VERSION
      settings["INFOPLIST_KEY_CFBundleVersion"] = CURRENT_PROJECT_VERSION
    else
      settings.delete("GENERATE_INFOPLIST_FILE")
    end

    settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id if bundle_id
  end
end

def add_swift_sources(target:, parent_group:, relative_folder:, exclude: [])
  folder_group = parent_group.new_group(File.basename(relative_folder), File.basename(relative_folder))
  absolute_folder = ROOT / relative_folder

  Dir.glob((absolute_folder / "**/*.swift").to_s).sort.each do |absolute_path|
    relative_path = Pathname(absolute_path).relative_path_from(absolute_folder).to_s
    next if exclude.include?(relative_path)

    file_ref = folder_group.new_file(relative_path)
    target.add_file_references([file_ref])
  end

  folder_group
end

def add_c_sources(target:, parent_group:, relative_folder:)
  folder_group = parent_group.new_group(File.basename(relative_folder), File.basename(relative_folder))
  absolute_folder = ROOT / relative_folder

  Dir.glob((absolute_folder / "**/*").to_s).sort.each do |absolute_path|
    next unless File.file?(absolute_path)

    relative_path = Pathname(absolute_path).relative_path_from(absolute_folder).to_s
    file_ref = folder_group.new_file(relative_path)

    case File.extname(absolute_path)
    when ".c"
      target.add_file_references([file_ref])
    when ".h"
      build_file = target.headers_build_phase.add_file_reference(file_ref, true)
      build_file.settings = { "ATTRIBUTES" => ["Public"] }
    end
  end

  folder_group
end

def add_resources(target:, parent_group:, relative_paths:)
  relative_paths.each do |relative_path|
    next unless (ROOT / relative_path).exist?

    file_ref = parent_group.new_file(File.basename(relative_path))
    target.resources_build_phase.add_file_reference(file_ref, true)
  end
end

def add_dependency(target:, dependency:)
  target.add_dependency(dependency)
  target.frameworks_build_phase.add_file_reference(dependency.product_reference, true)
end

smc_bridge_target = project.new_target(:static_library, "CellCapSMCBridge", :osx, "26.0")
shared_target = project.new_target(:framework, "Shared", :osx, "26.0")
system_support_target = project.new_target(:framework, "SystemSupport", :osx, "26.0")
core_target = project.new_target(:framework, "Core", :osx, "26.0")
app_target = project.new_target(:application, "AppUI", :osx, "26.0")
helper_target = project.new_target(:command_line_tool, "Helper", :osx, "26.0")
tests_target = project.new_target(:unit_test_bundle, "CoreTests", :osx, "26.0")

configure_build_settings(smc_bridge_target, generate_info_plist: false)
configure_build_settings(shared_target, bundle_id: "com.shin.cellcap.shared")
configure_build_settings(system_support_target, bundle_id: "com.shin.cellcap.systemsupport")
configure_build_settings(core_target, bundle_id: "com.shin.cellcap.core")
configure_build_settings(app_target, bundle_id: "com.shin.cellcap.app", enable_code_signing: true)
configure_build_settings(helper_target, generate_info_plist: false, enable_code_signing: true)
configure_build_settings(tests_target, bundle_id: "com.shin.cellcap.tests")

smc_bridge_target.build_configurations.each do |configuration|
  configuration.build_settings["DEFINES_MODULE"] = "YES"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
  configuration.build_settings["PRODUCT_NAME"] = "CellCapSMCBridge"
  configuration.build_settings["HEADER_SEARCH_PATHS"] = [
    "$(inherited)",
    "$(SRCROOT)/Sources/CellCapSMCBridge/include"
  ]
  configuration.build_settings["OTHER_LDFLAGS"] = [
    "$(inherited)",
    "-framework",
    "CoreFoundation",
    "-framework",
    "IOKit"
  ]
end

shared_target.build_configurations.each do |configuration|
  configuration.build_settings["DEFINES_MODULE"] = "YES"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
end

system_support_target.build_configurations.each do |configuration|
  configuration.build_settings["DEFINES_MODULE"] = "YES"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
end

core_target.build_configurations.each do |configuration|
  configuration.build_settings["DEFINES_MODULE"] = "YES"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
end

app_target.build_configurations.each do |configuration|
  configuration.build_settings["PRODUCT_NAME"] = "CellCap"
  configuration.build_settings["INFOPLIST_KEY_LSUIElement"] = "YES"
  configuration.build_settings["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@executable_path/../Frameworks",
    "@loader_path/../Frameworks"
  ]
end

helper_target.build_configurations.each do |configuration|
  configuration.build_settings["PRODUCT_NAME"] = "CellCapHelper"
  # SMAppService daemon은 앱 번들 안의 helper를 고정 식별자로 서명해야 하고,
  # base entitlement(com.apple.application-identifier 등)가 들어가면 launchd launch constraint에 걸릴 수 있다.
  configuration.build_settings["OTHER_CODE_SIGN_FLAGS"] = "-i com.shin.cellcap.helper"
  configuration.build_settings["CODE_SIGN_INJECT_BASE_ENTITLEMENTS"] = "NO"
  configuration.build_settings["ENTITLEMENTS_REQUIRED"] = "NO"
  configuration.build_settings["SKIP_INSTALL"] = "YES"
  configuration.build_settings["SWIFT_INCLUDE_PATHS"] = [
    "$(inherited)",
    "$(SRCROOT)/Sources/CellCapSMCBridge/include"
  ]
  configuration.build_settings["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@executable_path/../Frameworks",
    "@loader_path/../Frameworks"
  ]
end

tests_target.build_configurations.each do |configuration|
  configuration.build_settings["BUNDLE_LOADER"] = ""
  configuration.build_settings["TEST_HOST"] = ""
  configuration.build_settings["LD_RUNPATH_SEARCH_PATHS"] = [
    "$(inherited)",
    "@loader_path/../Frameworks"
  ]
end

add_c_sources(target: smc_bridge_target, parent_group: sources_group, relative_folder: "Sources/CellCapSMCBridge")
add_swift_sources(target: shared_target, parent_group: sources_group, relative_folder: "Sources/Shared")
add_swift_sources(target: system_support_target, parent_group: sources_group, relative_folder: "Sources/SystemSupport")
add_swift_sources(
  target: core_target,
  parent_group: sources_group,
  relative_folder: "Sources/Core"
)
app_group = add_swift_sources(target: app_target, parent_group: sources_group, relative_folder: "Sources/AppUI")
add_swift_sources(target: helper_target, parent_group: sources_group, relative_folder: "Sources/Helper")
add_swift_sources(target: tests_target, parent_group: tests_group, relative_folder: "Tests/CoreTests")

add_resources(
  target: app_target,
  parent_group: app_group,
  relative_paths: ["Sources/AppUI/Assets.xcassets"]
)

add_dependency(target: system_support_target, dependency: shared_target)
add_dependency(target: core_target, dependency: shared_target)
add_dependency(target: core_target, dependency: system_support_target)
add_dependency(target: app_target, dependency: shared_target)
add_dependency(target: app_target, dependency: system_support_target)
add_dependency(target: app_target, dependency: core_target)
add_dependency(target: helper_target, dependency: smc_bridge_target)
add_dependency(target: helper_target, dependency: shared_target)
add_dependency(target: helper_target, dependency: system_support_target)
add_dependency(target: tests_target, dependency: shared_target)
add_dependency(target: tests_target, dependency: core_target)
add_dependency(target: tests_target, dependency: helper_target)
add_dependency(target: tests_target, dependency: system_support_target)

embed_frameworks_phase = app_target.new_copy_files_build_phase("Embed Frameworks")
embed_frameworks_phase.symbol_dst_subfolder_spec = :frameworks
[shared_target, system_support_target, core_target].each do |framework_target|
  build_file = embed_frameworks_phase.add_file_reference(framework_target.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
end

# SMAppService.daemon(plistName:)이 찾는 위치에 helper와 LaunchDaemon plist를 넣는다.
# helper는 자체 target에서 이미 서명했으므로 복사 단계에서 다시 서명하지 않는다.
app_target.add_dependency(helper_target)
embed_helper_phase = app_target.new_copy_files_build_phase("Embed Helper Tool")
embed_helper_phase.symbol_dst_subfolder_spec = :executables
embed_helper_phase.add_file_reference(helper_target.product_reference, true)

launch_daemon_plist = "BuildSupport/dev/LaunchDaemons/com.shin.cellcap.helper.plist"
embed_plist_phase = app_target.new_shell_script_build_phase("Embed Helper LaunchDaemon plist")
embed_plist_phase.input_paths = ["$(SRCROOT)/#{launch_daemon_plist}"]
embed_plist_phase.output_paths = ["$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/com.shin.cellcap.helper.plist"]
embed_plist_phase.shell_script = <<~SCRIPT
  set -e
  DEST="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
  mkdir -p "$DEST"
  cp "$SRCROOT/#{launch_daemon_plist}" "$DEST/com.shin.cellcap.helper.plist"
SCRIPT

project.sort
project.save
