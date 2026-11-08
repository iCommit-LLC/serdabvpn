#!/usr/bin/env ruby
# Wires the SerdabTunnel network extension into ios/Runner.xcodeproj, the way
# WireGuard's own README says to: WireGuardKit as a Swift package (vendored in
# ios/WireGuardKit) plus the Go bridge as an external build target. Refuses to
# run twice. Needs the xcodeproj gem (CocoaPods ships it).
require 'xcodeproj'

TEAM = ENV.fetch('TEAM', 'NS8D5TU55D')

proj = Xcodeproj::Project.open(File.expand_path('../ios/Runner.xcodeproj', __dir__))
abort 'SerdabTunnel is already in the project' if proj.targets.any? { |t| t.name == 'SerdabTunnel' }
runner = proj.targets.find { |t| t.name == 'Runner' }

# -- the extension target ----------------------------------------------------
ext = proj.new_target(:app_extension, 'SerdabTunnel', :ios, '15.0')
grp = proj.main_group.new_group('SerdabTunnel', 'SerdabTunnel')
ext.add_file_references(%w[PacketTunnelProvider.swift TunnelConfiguration+WgQuickConfig.swift String+ArrayConversion.swift].map { |f| grp.new_file(f) })
%w[Info.plist SerdabTunnel.entitlements].each { |f| grp.new_file(f) }
xcconfig = grp.new_file('Flutter.xcconfig')
ext.build_configurations.each do |c|
  c.base_configuration_reference = xcconfig # FLUTTER_BUILD_NAME / NUMBER, so both bundles carry pubspec's version
  c.build_settings.merge!(
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.serdabvpn.tunnel',
    'INFOPLIST_FILE' => 'SerdabTunnel/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'SerdabTunnel/SerdabTunnel.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => TEAM,
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'ENABLE_BITCODE' => 'NO',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'SKIP_INSTALL' => 'YES',
    'LIBRARY_SEARCH_PATHS' => ['$(inherited)', '$(BUILT_PRODUCTS_DIR)'],
  )
end

# -- WireGuardKit, the vendored Swift package -----------------------------------
pkg = proj.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
pkg.relative_path = 'WireGuardKit'
proj.root_object.package_references << pkg
dep = proj.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'WireGuardKit'
ext.package_product_dependencies << dep
bf = proj.new(Xcodeproj::Project::Object::PBXBuildFile)
bf.product_ref = dep
ext.frameworks_build_phase.files << bf

# -- the Go bridge: SPM cannot build it, so an external target runs its Makefile
go = proj.new(Xcodeproj::Project::Object::PBXLegacyTarget)
go.name = 'WireGuardGoBridgeiOS'
go.product_name = 'WireGuardGoBridgeiOS'
go.build_tool_path = '/usr/bin/make'
go.build_arguments_string = '$(ACTION)'
go.build_working_directory = '$(SRCROOT)/WireGuardKit/Sources/WireGuardKitGo'
go.pass_build_settings_in_environment = '1'
list = proj.new(Xcodeproj::Project::Object::XCConfigurationList)
list.default_configuration_is_visible = '0'
list.default_configuration_name = 'Release'
proj.build_configurations.each do |pc|
  bc = proj.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  bc.name = pc.name
  bc.build_settings = { 'SDKROOT' => 'iphoneos', 'PRODUCT_NAME' => '$(TARGET_NAME)' }
  list.build_configurations << bc
end
go.build_configuration_list = list
proj.targets << go
ext.add_dependency(go)

# -- Runner: embed the extension, entitlement, channel source, iOS 15 ----------
runner_grp = proj.main_group['Runner']
runner.add_file_references([runner_grp.new_file('TunnelChannel.swift')])
runner_grp.new_file('Runner.entitlements')
runner.add_dependency(ext)
embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.dst_path = ''
embed.add_file_reference(ext.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# Flutter's "Thin Binary" script must run after the extension is copied in, or Xcode reports a cycle.
thin = runner.build_phases.find { |ph| ph.isa == 'PBXShellScriptBuildPhase' && ph.name == 'Thin Binary' }
if thin
  runner.build_phases.delete(embed)
  runner.build_phases.insert(runner.build_phases.index(thin), embed)
end
runner.build_configurations.each do |c|
  c.build_settings.merge!(
    'IPHONEOS_DEPLOYMENT_TARGET' => '15.0',
    'CODE_SIGN_ENTITLEMENTS' => 'Runner/Runner.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => TEAM,
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
  )
end
proj.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0' }

proj.save
puts "ok: SerdabTunnel + WireGuardGoBridgeiOS added, team #{TEAM}"
