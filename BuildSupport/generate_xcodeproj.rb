#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "xcodeproj"

ROOT = Pathname(__dir__).parent.expand_path
PROJECT_PATH = ROOT / "CellCap.xcodeproj"

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes["LastSwiftUpdateCheck"] = "2600"
project.root_object.attributes["LastUpgradeCheck"] = "2600"
project.root_object.development_region = "ko"

sources_group = project.main_group.new_group("Sources", "Sources")
tests_group = project.main_group.new_group("Tests", "Tests")
docs_group = project.main_group.new_group("Docs")
docs_group.new_file("../README.md")
docs_group.new_file("../01_기획서.md")
docs_group.new_file("../02_Prompts.md")
docs_group.new_file("../03_공개API_충전제어_검토.md")

def configure_build_settings(target, bundle_id: nil, generate_info_plist: true)
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings["MACOSX_DEPLOYMENT_TARGET"] = "26.0"
    settings["SDKROOT"] = "macosx"
    settings["SWIFT_VERSION"] = "6.0"
    settings["SWIFT_STRICT_CONCURRENCY"] = "complete"
    settings["CODE_SIGNING_ALLOWED"] = "NO"
    settings["ENABLE_HARDENED_RUNTIME"] = "NO"
    settings["CLANG_ENABLE_MODULES"] = "YES"

    if generate_info_plist
      settings["GENERATE_INFOPLIST_FILE"] = "YES"
    else
      settings.delete("GENERATE_INFOPLIST_FILE")
    end

    settings["PRODUCT_BUNDLE_IDENTIFIER"] = bundle_id if bundle_id
  end
end

def add_swift_sources(target:, parent_group:, relative_folder:)
  folder_group = parent_group.new_group(File.basename(relative_folder), File.basename(relative_folder))
  absolute_folder = ROOT / relative_folder

  Dir.glob((absolute_folder / "**/*.swift").to_s).sort.each do |absolute_path|
    relative_path = Pathname(absolute_path).relative_path_from(absolute_folder).to_s
    file_ref = folder_group.new_file(relative_path)
    target.add_file_references([file_ref])
  end
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
end

def add_dependency(target:, dependency:)
  target.add_dependency(dependency)
  target.frameworks_build_phase.add_file_reference(dependency.product_reference, true)
end

smc_bridge_target = project.new_target(:static_library, "CellCapSMCBridge", :osx, "26.0")
shared_target = project.new_target(:framework, "Shared", :osx, "26.0")
core_target = project.new_target(:framework, "Core", :osx, "26.0")
app_target = project.new_target(:application, "AppUI", :osx, "26.0")
helper_target = project.new_target(:command_line_tool, "Helper", :osx, "26.0")
tests_target = project.new_target(:unit_test_bundle, "CoreTests", :osx, "26.0")

configure_build_settings(smc_bridge_target, generate_info_plist: false)
configure_build_settings(shared_target, bundle_id: "com.shin.cellcap.shared")
configure_build_settings(core_target, bundle_id: "com.shin.cellcap.core")
configure_build_settings(app_target, bundle_id: "com.shin.cellcap.app")
configure_build_settings(helper_target, generate_info_plist: false)
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
add_swift_sources(target: core_target, parent_group: sources_group, relative_folder: "Sources/Core")
add_swift_sources(target: app_target, parent_group: sources_group, relative_folder: "Sources/AppUI")
add_swift_sources(target: helper_target, parent_group: sources_group, relative_folder: "Sources/Helper")
add_swift_sources(target: tests_target, parent_group: tests_group, relative_folder: "Tests/CoreTests")

add_dependency(target: core_target, dependency: shared_target)
add_dependency(target: app_target, dependency: shared_target)
add_dependency(target: app_target, dependency: core_target)
add_dependency(target: helper_target, dependency: smc_bridge_target)
add_dependency(target: helper_target, dependency: core_target)
add_dependency(target: helper_target, dependency: shared_target)
add_dependency(target: tests_target, dependency: shared_target)
add_dependency(target: tests_target, dependency: core_target)
add_dependency(target: tests_target, dependency: helper_target)

embed_frameworks_phase = app_target.new_copy_files_build_phase("Embed Frameworks")
embed_frameworks_phase.symbol_dst_subfolder_spec = :frameworks
[shared_target, core_target].each do |framework_target|
  build_file = embed_frameworks_phase.add_file_reference(framework_target.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
end

project.sort
project.save
